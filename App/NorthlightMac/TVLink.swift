import CryptoKit
import Foundation
import Network
import NorthlightKit
import Observation

/// The editor's connection to the Apple TV, held while the editor is open and apart
/// from agent sharing. The TV's layout is the truth: an edit goes out on the revision
/// it was made on, and the TV's echo replaces it, whether it applied or not.
@MainActor
@Observable
final class TVLink {
    enum State: Equatable {
        case looking
        case connecting(String)
        case connected(String)
        case unreachable(String)
        /// The two ends speak different protocol versions; the text says which to update.
        case outdated(String)
        case unpaired
    }

    private(set) var state = State.looking
    /// The layout on the TV, or the edit on its way there.
    private(set) var dashboard: Dashboard?
    private(set) var status: TVStatus?
    /// From sending a frame to the TV's answer, the last time one was timed.
    private(set) var roundTrip: Duration?
    /// Counts layouts from the TV that no edit here caused, after which undoing would
    /// replay a layout the TV no longer has.
    private(set) var foreignChanges = 0

    var canEdit: Bool {
        if case .connected = state, dashboard != nil, status?.editing != true { true } else { false }
    }

    private var revision: LayoutRevision?
    /// The edit sent and not yet echoed, and the newer one waiting behind it.
    private var sent: (base: LayoutRevision, at: ContinuousClock.Instant)?
    private var queued: Dashboard?
    private var debounce: Task<Void, Never>?
    private var helloSent: ContinuousClock.Instant?
    private var browser: NWBrowser?
    private var endpoint: NWEndpoint?
    private var connection: BridgeConnection?
    private var running: Task<Void, Never>?
    private let installID = UUID()

    #if DEBUG
    private let key: SymmetricKey? = Bridge.developmentKey
    #else
    private let key: SymmetricKey? = nil
    #endif

    func start() {
        guard running == nil else { return }
        guard key != nil else {
            state = .unpaired
            return
        }
        let browser = NWBrowser(for: .bonjour(type: Bridge.serviceType, domain: nil), using: .tcp)
        // A `-tv <name>` launch picks that TV among several, for tests against a simulator.
        let wanted = UserDefaults.standard.string(forKey: "tv")
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let endpoint = results.first { result in
                guard let wanted else { return true }
                if case .service(let name, _, _, _) = result.endpoint { return name == wanted }
                return false
            }?.endpoint
            Task { @MainActor in self?.endpoint = endpoint }
        }
        browser.start(queue: .main)
        self.browser = browser
        running = Task { await run() }
    }

    func stop() {
        running?.cancel()
        running = nil
        browser?.cancel()
        browser = nil
        connection?.cancel()
        connection = nil
    }

    /// Shows the edit at once and sends it 100 ms after the last change, so a drag's
    /// steps go as one.
    func edit(_ next: Dashboard, undo: UndoManager?) {
        guard canEdit, let previous = dashboard, next != previous else { return }
        undo?.registerUndo(withTarget: self) { link in
            MainActor.assumeIsolated { link.edit(previous, undo: undo) }
        }
        dashboard = next
        queued = next
        debounce?.cancel()
        debounce = Task {
            try? await Task.sleep(for: .milliseconds(100))
            guard !Task.isCancelled else { return }
            await sendQueued()
        }
    }

    func show(page: UUID) {
        guard canEdit, let connection else { return }
        status?.page = page
        Task { try? await connection.send(.showPage(page)) }
    }

    /// One edit in flight at a time, since the next must be built on the revision the
    /// TV answers with.
    private func sendQueued() async {
        guard sent == nil, let next = queued, let revision, let connection else { return }
        queued = nil
        sent = (revision, .now)
        try? await connection.send(.layout(LayoutFrame(revision: revision, base: revision, dashboard: next)))
    }

    private func run() async {
        while !Task.isCancelled {
            guard let endpoint, let key else {
                if case .unreachable = state {} else if dashboard == nil { state = .looking }
                try? await Task.sleep(for: .seconds(1))
                continue
            }
            let name = if case .service(let name, _, _, _) = endpoint { name } else { "Apple TV" }
            state = .connecting(name)
            let fresh = BridgeConnection(to: endpoint, key: key)
            do {
                try await fresh.ready()
                connection = fresh
                helloSent = .now
                try await fresh.send(.hello(Hello(installID: installID, revision: nil, editing: false)))
                for await frame in fresh.frames { receive(frame, from: name) }
            } catch {}
            fresh.cancel()
            connection = nil
            sent = nil
            queued = nil
            if case .outdated = state {} else { state = .unreachable(name) }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func receive(_ frame: Frame, from name: String) {
        switch frame {
        case .hello(let hello):
            if let helloSent { roundTrip = .now - helloSent }
            helloSent = nil
            if hello.protocolVersion > Hello.currentProtocol {
                state = .outdated("Update Northlight on the Mac")
            } else if hello.protocolVersion < Hello.currentProtocol {
                state = .outdated("Update Northlight on the Apple TV")
            } else {
                state = .connected(name)
            }
        case .layout(let layout):
            if let sent, layout.base == sent.base {
                roundTrip = .now - sent.at
                self.sent = nil
            } else if sent != nil || queued != nil || layout.revision != revision {
                // The TV refused the edit or changed on its own: its layout stands.
                sent = nil
                queued = nil
                foreignChanges += 1
            }
            revision = layout.revision
            if queued == nil { dashboard = layout.dashboard }
            Task { await sendQueued() }
        case .tvStatus(let next):
            status = status.map(next.filled(from:)) ?? next
        case .agents, .briefingRequest, .briefing, .showPage, .usage, .events, .github, .disconnected:
            break
        }
    }
}
