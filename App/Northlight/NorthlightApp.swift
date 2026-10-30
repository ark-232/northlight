import SwiftUI
import UIKit
import NorthlightKit
import NorthlightUI

@main
struct NorthlightApp: App {
    @State private var settings = Settings.load(from: .standard)
    @State private var calendarURL = Keychain.read(.calendarURL).flatMap { URL(string: $0) }
    @State private var githubToken = Keychain.read(.githubToken)
    @State private var icloud = Keychain.read(.icloud).flatMap { try? JSONDecoder().decode(ICloudAccount.self, from: Data($0.utf8)) }
    @State private var layout = TVLayout.load(from: .standard)
    /// The last revision every Mac was told of.
    @State private var echoed: LayoutRevision?
    /// Editing, removing or adding on the TV, when a Mac's layout would be lost under it.
    @State private var busy = false
    @State private var store: DashboardStore?
    @State private var editingSettings = false
    @AppStorage("speedTestConsent") private var speedTestConsent = false
    @AppStorage("speedTestsAutomatic") private var speedTestsAutomatic = false
    /// Seconds since 1970; zero when none is drawn.
    @AppStorage("speedTestNext") private var speedTestNext = 0.0
    @Environment(\.scenePhase) private var scenePhase
    /// The page on screen, by index. A launch starts on the first page, or on the one
    /// a `-page` argument names, for screenshots.
    @State private var page = UserDefaults.standard.integer(forKey: "page")

    var body: some Scene {
        WindowGroup {
            Group {
                if let store {
                    DashboardView(store: store, dashboard: $layout.dashboard, pageIndex: $page, busy: $busy,
                                  settingsOpen: editingSettings) {
                        editingSettings = true
                    }
                        // The place's zone is the dashboard's one clock.
                        .environment(\.timeZone, store.config.place.timeZone)
                        .environment(\.calendar, store.config.place.calendar)
                        .fullScreenCover(isPresented: $editingSettings) {
                            SettingsView(settings: $settings, calendarURL: $calendarURL, githubToken: $githubToken, icloud: $icloud,
                                         dashboard: $layout.dashboard) {
                                editingSettings = false
                            }
                        }
                } else {
                    SettingsView(settings: $settings, calendarURL: $calendarURL, githubToken: $githubToken, icloud: $icloud)
                }
            }
            // Feeds stay metric; the locale picks the units every view formats in.
            .environment(\.locale, settings.units.map { $0.locale(over: .autoupdatingCurrent) } ?? .autoupdatingCurrent)
            .task(id: StoreInputs(place: settings.place, calendarURL: calendarURL, githubToken: githubToken,
                                  icloud: icloud)) { rebuildStore() }
            .onChange(of: settings) { _, settings in settings.save(to: .standard) }
            .onChange(of: settings.units) { _, units in store?.units = units }
            .task(id: automaticSpeedTests) { await runAutomaticSpeedTests() }
            // The layout on screen is kept on this TV, and runs the feeds its widgets show.
            .onChange(of: layout, initial: true) { _, layout in
                try? layout.save(to: .standard)
                store.map { $0.run(Feed.needed(by: layout.dashboard, config: $0.config)) }
                if layout.revision != echoed {
                    echoed = layout.revision
                    store?.sendToMacs(.layout(layout.frame()))
                }
            }
            .onChange(of: busy) { tellMacs(full: false) }
            .onChange(of: page) { tellMacs(full: false) }
            .task(id: store.map(ObjectIdentifier.init)) {
                while !Task.isCancelled {
                    tellMacs(full: true)
                    try? await Task.sleep(for: .seconds(30))
                }
            }
            // This is what makes the dashboard always-on: with the idle timer
            // disabled, tvOS suppresses both the screensaver and sleep while this
            // app is frontmost. It is the closest tvOS allows to a custom
            // screensaver; there is no API to replace the system one.
            .onChange(of: scenePhase, initial: true) { _, phase in
                UIApplication.shared.isIdleTimerDisabled = phase == .active
            }
        }
    }

    /// The store to test on, while the viewer has agreed to speed tests, asked for them
    /// to run on their own, has the app in front, and has a Network widget to show them.
    private var automaticSpeedTests: ObjectIdentifier? {
        guard speedTestConsent, speedTestsAutomatic, scenePhase == .active, let store,
              layout.dashboard.pages.contains(where: { $0.placements.contains { $0.config == .network } })
        else { return nil }
        return ObjectIdentifier(store)
    }

    private func runAutomaticSpeedTests() async {
        guard automaticSpeedTests != nil, let store else { return }
        while !Task.isCancelled {
            // The drawn time outlives the app leaving the front, so coming back does not
            // draw again.
            if speedTestNext == 0 {
                speedTestNext = SpeedSchedule.next(from: .now, history: store.speedTests.map(\.date),
                                                   uniform: .random(in: 0..<1)).timeIntervalSince1970
            }
            try? await Task.sleep(for: .seconds(max(0, speedTestNext - Date.now.timeIntervalSince1970)))
            guard !Task.isCancelled else { return }
            speedTestNext = 0
            if let path = store.path, path.link != nil, !path.isMetered {
                store.runSpeedTest()
            }
        }
    }

    private func rebuildStore() {
        store?.stop()
        store = settings.place.map { place in
            var config = Config(
                place: place,
                calendarICSURL: calendarURL,
                // api.weather.gov requires a contact in the User-Agent. The repo URL
                // satisfies that without putting a personal address on the wire.
                contact: "github.com/ark-232/northlight"
            )
            config.githubToken = githubToken
            config.icloud = icloud
            #if DEBUG
            config.bridgeKey = Bridge.developmentKey
            #endif
            let next = DashboardStore(config: config)
            next.units = settings.units
            next.onEditorFrame = { fromMac($0) }
            next.run(Feed.needed(by: layout.dashboard, config: next.config))
            return next
        }
    }

    private var shownPage: Page {
        layout.dashboard.pages[min(page, layout.dashboard.pages.count - 1)]
    }

    private func tellMacs(full: Bool) {
        guard let store else { return }
        store.sendToMacs(.tvStatus(store.status(editing: busy, page: shownPage.id, full: full)))
    }

    /// The Mac's editor. Until pairing gives each TV its own key, only debug builds,
    /// whose key anyone can derive, take a layout or a page turn from it.
    private func fromMac(_ frame: Frame) {
        guard let store else { return }
        switch frame {
        case .hello:
            store.sendToMacs(.hello(Hello(installID: layout.revision.epoch, revision: layout.revision, editing: busy)))
            store.sendToMacs(.layout(layout.frame()))
            tellMacs(full: true)
        case .layout(let proposal):
            #if DEBUG
            let shown = shownPage.id
            let echo = layout.receive(proposal, refusing: busy)
            echoed = layout.revision
            page = layout.dashboard.pages.firstIndex { $0.id == shown } ?? min(page, layout.dashboard.pages.count - 1)
            store.sendToMacs(.layout(echo))
            #else
            store.sendToMacs(.layout(layout.frame()))
            #endif
        case .showPage(let id):
            #if DEBUG
            if !busy, let index = layout.dashboard.pages.firstIndex(where: { $0.id == id }) { page = index }
            #endif
            tellMacs(full: false)
        case .agents, .briefingRequest, .briefing, .tvStatus, .usage, .events, .github, .disconnected:
            break
        }
    }

    private struct StoreInputs: Hashable {
        let place: Place?
        let calendarURL: URL?
        let githubToken: String?
        let icloud: ICloudAccount?
    }
}
