import AppKit
import CryptoKit
import Foundation
import Network
import NorthlightAgent
import NorthlightKit
import Observation

/// Watches this Mac's Claude Code sessions and, while sharing is on, reports them to
/// the Apple TV over the bridge and writes the briefings the TV asks for.
@MainActor
@Observable
final class AgentFeed {
    enum TV: Equatable {
        case looking
        case found(String)
        case showing(String)
        case unpaired
    }

    /// What the TV is shown, redaction applied.
    private(set) var statuses: [AgentStatus] = []
    private(set) var tv = TV.looking
    /// Claude Code's projects folder, once the person has granted it.
    private(set) var folder: URL?
    /// The Claude account's usage, from the statusLine wrapper; nil until it has written.
    private(set) var usage: UsageReading?

    /// Where the wrapper writes: inside this app's container, so the sandbox needs no grant.
    static let usageFile = URL.applicationSupportDirectory.appending(path: "Northlight/usage.json")
    /// The wrapper, bundled so it can be copied into place.
    static let usageScript = Bundle.main.url(forResource: "northlight-statusline", withExtension: "sh")

    /// Off until the person turns it on, so nothing leaves the Mac before they have
    /// seen what would, and the system's local network prompt comes when it means
    /// something.
    var sharing: Bool {
        didSet {
            defaults.set(sharing, forKey: "sharing")
            browse(sharing)
        }
    }

    /// Fragments of names and paths whose sessions show only as busy.
    var blocked: [String] {
        didSet {
            defaults.set(blocked, forKey: "blocked")
            let redaction = AgentRedaction(blockedPathFragments: blocked)
            Task { await watcher?.redact(with: redaction) }
        }
    }

    /// The connectors' latest pushes, sent to each TV as it connects.
    var connectorFrames: @MainActor () -> [Frame] = { [] }
    /// The TV's place from its last briefing request, so the connectors read dates
    /// in the TV's zone.
    private(set) var place: Place?

    private let defaults = UserDefaults.standard
    private var watcher: SessionWatcher?
    private var browser: NWBrowser?
    private var endpoint: NWEndpoint?
    private var connection: BridgeConnection?
    private var lastSent: (statuses: [AgentStatus], at: Date)?
    private var usageModified: Date?
    private var usageSent: UsageReading?

    #if DEBUG
    private let key: SymmetricKey? = Bridge.developmentKey
    #else
    private let key: SymmetricKey? = nil
    #endif

    init() {
        sharing = defaults.bool(forKey: "sharing")
        blocked = defaults.stringArray(forKey: "blocked") ?? []
        if let bookmark = defaults.data(forKey: "projectsFolder") {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, bookmarkDataIsStale: &stale),
               url.startAccessingSecurityScopedResource() {
                if stale { remember(url) }
                open(url)
            }
        }
        browse(sharing)
        Task { await run() }
    }

    private func browse(_ on: Bool) {
        browser?.cancel()
        browser = nil
        endpoint = nil
        guard on else { return }
        let browser = NWBrowser(for: .bonjour(type: Bridge.serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let endpoint = results.first?.endpoint
            Task { @MainActor in self?.endpoint = endpoint }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    /// Asks for Claude Code's projects folder, which the sandbox keeps from the app
    /// until the person picks it.
    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.showsHiddenFiles = true
        // Opening one level up shows "projects" as the one thing to pick; opened inside
        // it, the panel offers each project and reads as a pick of single chats.
        let claude = URL(filePath: String(cString: getpwuid(getuid())!.pointee.pw_dir)).appending(path: ".claude")
        panel.directoryURL = claude
        panel.message = "Select the “projects” folder to share every Claude Code session, then click Allow."
        panel.prompt = "Allow"
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folder?.stopAccessingSecurityScopedResource()
        remember(url)
        if url.startAccessingSecurityScopedResource() { open(url) }
    }

    private func remember(_ folder: URL) {
        defaults.set(try? folder.bookmarkData(options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess]),
                     forKey: "projectsFolder")
    }

    private func open(_ url: URL) {
        folder = url
        watcher = SessionWatcher(root: url, redaction: AgentRedaction(blockedPathFragments: blocked))
    }

    private func run() async {
        while !Task.isCancelled {
            statuses = await watcher?.statuses() ?? []
            readUsage()
            if sharing {
                await report()
            } else if let connection {
                // The TV clears the tile now rather than when the reports stop.
                try? await connection.send(.agents([]))
                connection.cancel()
                self.connection = nil
                lastSent = nil
                usageSent = nil
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    /// Reads the wrapper's file when it has been written since the last look.
    private func readUsage() {
        let modified = (try? FileManager.default.attributesOfItem(atPath: Self.usageFile.path))?[.modificationDate] as? Date
        guard let modified, modified != usageModified else { return }
        usageModified = modified
        if let data = try? Data(contentsOf: Self.usageFile),
           let reading = try? JSONDecoder().decode(UsageReading.self, from: data) {
            usage = reading
        }
    }

    /// The wrapper rewrites the file on every status line; the TV hears of new figures,
    /// or every five minutes of the same ones so it knows they are still current.
    private var usageChanged: Bool {
        guard let usage else { return false }
        guard let usageSent else { return true }
        return usage.fiveHour != usageSent.fiveHour || usage.sevenDay != usageSent.sevenDay
            || usage.observedAt.timeIntervalSince(usageSent.observedAt) >= 5 * 60
    }

    /// Writes each briefing the TV asks for, until the TV goes. The model runs on this
    /// Mac, so the day's facts go no further.
    private func answer(_ connection: BridgeConnection) async {
        for await frame in connection.frames {
            guard case .briefingRequest(let request) = frame else { continue }
            place = request.place
            try? await connection.send(.briefing(await BriefingWriter.write(request)))
        }
    }

    /// Sends a connector's push to the TV connected now, if one is. A TV that
    /// connects later gets the latest from `connectorFrames`.
    func push(_ frame: Frame) async {
        try? await connection?.send(frame)
    }

    /// Sends a change at once and repeats the last report, which is how the TV knows
    /// the Mac is still here.
    private func report() async {
        guard let key else {
            tv = .unpaired
            return
        }
        guard let endpoint else {
            tv = .looking
            return
        }
        let name = if case .service(let name, _, _, _) = endpoint { name } else { "Apple TV" }
        if connection == nil {
            let fresh = BridgeConnection(to: endpoint, key: key)
            do {
                try await fresh.ready()
                guard sharing else {
                    fresh.cancel()
                    return
                }
                connection = fresh
                lastSent = nil
                usageSent = nil
                Task { await answer(fresh) }
                for frame in connectorFrames() { try? await fresh.send(frame) }
            } catch {
                fresh.cancel()
                tv = .found(name)
                return
            }
        }
        if let lastSent, lastSent.statuses == statuses, Date().timeIntervalSince(lastSent.at) < AgentReport.repeatInterval,
           !usageChanged { return }
        do {
            try await connection?.send(.agents(statuses))
            lastSent = (statuses, Date())
            if usageChanged, let usage {
                try await connection?.send(.usage(usage))
                usageSent = usage
            }
            tv = .showing(name)
        } catch {
            connection?.cancel()
            connection = nil
            tv = .found(name)
        }
    }
}
