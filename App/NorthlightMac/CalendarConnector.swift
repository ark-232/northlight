import AppKit
import EventKit
import NorthlightAgent
import NorthlightKit
import Observation
import SystemConfiguration

/// Reads the agenda from the calendars this Mac's user picks, through EventKit, and
/// pushes it to the TV. iCloud, Google and Exchange arrive through Internet Accounts,
/// so no password reaches Northlight.
@MainActor
@Observable
final class CalendarConnector {
    struct Account: Identifiable {
        let id: String
        let title: String
        let calendars: [Item]
    }

    struct Item: Identifiable {
        let id: String
        let title: String
        let color: NSColor
    }

    private(set) var access = EKEventStore.authorizationStatus(for: .event)
    private(set) var accounts: [Account] = []
    /// What was last sent, or why nothing was.
    private(set) var status = ""

    /// Calendar identifiers to share. None until the person picks, so nothing leaves
    /// the Mac before they have chosen it.
    var chosen: Set<String> {
        didSet {
            defaults.set(Array(chosen), forKey: "calendars.chosen")
            push()
        }
    }

    var hasAccess: Bool { access == .fullAccess }

    private let store = EKEventStore()
    private let feed: AgentFeed
    private let defaults = UserDefaults.standard
    private var lastPushed: Pushed<[CalendarEvent]>?
    private var debounce: Task<Void, Never>?

    /// The latest push, for a TV that connects after it.
    var frame: Frame? { lastPushed.map { .events($0) } }

    init(feed: AgentFeed) {
        self.feed = feed
        chosen = Set(defaults.stringArray(forKey: "calendars.chosen") ?? [])
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.changed() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.store.refreshSourcesIfNecessary() }
        }
        reload()
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(DashboardStore.Cadence.calendar))
                guard let self else { return }
                store.refreshSourcesIfNecessary()
                push()
            }
        }
    }

    /// Asks macOS for full access to events, which shows the system prompt once.
    func grant() async {
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            status = "macOS refused calendar access: \(error.localizedDescription)"
        }
        access = EKEventStore.authorizationStatus(for: .event)
        // A first grant shows every calendar; unticking hides one.
        if hasAccess, chosen.isEmpty {
            chosen = Set(store.calendars(for: .event).map(\.calendarIdentifier))
        }
        reload()
    }

    func openPrivacySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
    }

    /// A store change often comes in a burst, as when an account syncs.
    private func changed() {
        debounce?.cancel()
        debounce = Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard !Task.isCancelled else { return }
            self?.reload()
        }
    }

    private func reload() {
        access = EKEventStore.authorizationStatus(for: .event)
        guard hasAccess else {
            accounts = []
            push()
            return
        }
        let calendars = store.calendars(for: .event)
        accounts = Dictionary(grouping: calendars) { $0.source?.sourceIdentifier ?? "" }
            .map { id, calendars in
                Account(id: id, title: calendars.first?.source?.title ?? "Other",
                        calendars: calendars.map { Item(id: $0.calendarIdentifier, title: $0.title, color: $0.color) }
                            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending })
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        push()
    }

    /// Sends the chosen calendars' agenda, or tells the TV to forget it once none is
    /// chosen or access is gone.
    private func push() {
        let calendars = hasAccess ? store.calendars(for: .event).filter { chosen.contains($0.calendarIdentifier) } : []
        guard !calendars.isEmpty else {
            status = hasAccess ? "No calendar chosen" : ""
            if lastPushed != nil {
                lastPushed = nil
                Task { await feed.push(.disconnected(.calendar)) }
            }
            return
        }
        let place = feed.place?.calendar ?? .current
        guard let window = try? DateInterval.agenda(calendar: place) else { return }
        let predicate = store.predicateForEvents(withStart: window.start, end: window.end, calendars: calendars)
        let events = store.events(matching: predicate).map { event in
            MacEvent(identifier: event.calendarItemIdentifier, occurrence: event.occurrenceDate ?? event.startDate,
                     title: event.title, location: event.location, start: event.startDate, end: event.endDate,
                     isAllDay: event.isAllDay)
                .calendarEvent(macCalendar: .current, placeCalendar: place)
        }
        .sorted { $0.start < $1.start }
        let pushed = Pushed(value: events, fetchedAt: Date(), interval: DashboardStore.Cadence.calendar, source: Mac.name)
        lastPushed = pushed
        status = "\(events.count) events in the next two weeks"
        Task { await feed.push(.events(pushed)) }
    }
}

enum Mac {
    /// The name the person gave this Mac, as the TV says where a value came from.
    static var name: String {
        SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "your Mac"
    }
}
