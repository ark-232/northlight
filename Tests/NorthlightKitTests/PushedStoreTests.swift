import CryptoKit
import Foundation
import Testing
@testable import NorthlightKit

private let now = Date()

private func config(calendar: Bool = false) -> Config {
    Config(place: Place(name: "Reykjavík", latitude: 64.1466, longitude: -21.9426,
                        timeZoneIdentifier: "Atlantic/Reykjavik", countryCode: "IS"),
           calendarICSURL: calendar ? URL(string: "https://example.com/cal.ics") : nil, contact: "test")
}

private func scratchCache() -> Cache {
    Cache(name: "NorthlightTests/\(UUID().uuidString)")
}

private func events(fetched secondsAgo: TimeInterval) -> Pushed<[CalendarEvent]> {
    Pushed(value: Samples.events(at: now), fetchedAt: now.addingTimeInterval(-secondsAgo), interval: 600, source: "Studio Mac")
}

private let githubPush = Pushed(value: GitHubPush(summary: Samples.github(at: now), codeHistory: Samples.codeHistory(at: now)),
                                fetchedAt: now, interval: 900, source: "Studio Mac")

@MainActor @Suite struct PushedStoreTests {
    @Test func aPushFillsAnAgendaTheTVHasNoCalendarFor() {
        let store = DashboardStore(config: config(), http: HTTP(userAgent: "test"), macCache: scratchCache())
        #expect(store.agenda(asOf: now) == nil)
        store.receive(.events(events(fetched: 10)))
        #expect(store.agenda(asOf: now)?.state(asOf: now) == .ready(Samples.events(at: now)))
    }

    @Test func aFreshPushWinsOverTheTVsOwnCalendarUntilThreeIntervalsPass() {
        let store = DashboardStore(config: config(calendar: true), http: HTTP(userAgent: "test"), macCache: scratchCache())
        store.receive(.events(events(fetched: 1_790)))
        #expect(store.agenda(asOf: now)?.state(asOf: now) == .ready(Samples.events(at: now)))
        store.receive(.events(events(fetched: 1_810)))
        // The TV's own feed has not answered yet.
        #expect(store.agenda(asOf: now)?.state(asOf: now) == .loading)
    }

    @Test func aQuietMacsPushReadsUnavailableWhenTheTVHasNoCalendar() {
        let store = DashboardStore(config: config(), http: HTTP(userAgent: "test"), macCache: scratchCache())
        store.receive(.events(events(fetched: 1_810)))
        #expect(store.agenda(asOf: now)?.state(asOf: now) == .unavailable("Not updated by Studio Mac lately"))
    }

    @Test func aPushedErrorWithoutAValueLeavesTheTVsOwnCalendar() {
        let store = DashboardStore(config: config(calendar: true), http: HTTP(userAgent: "test"), macCache: scratchCache())
        store.receive(.events(Pushed(value: nil, fetchedAt: now, error: "Calendar access is off", interval: 600, source: "Studio Mac")))
        #expect(store.agenda(asOf: now)?.state(asOf: now) == .loading)
    }

    @Test func aGitHubPushFillsTheSummaryAndTheLines() {
        let store = DashboardStore(config: config(), http: HTTP(userAgent: "test"), macCache: scratchCache())
        #expect(store.githubFeed(asOf: now) == nil)
        store.receive(.github(githubPush))
        #expect(store.githubFeed(asOf: now)?.state(asOf: now) == .ready(Samples.github(at: now)))
        #expect(store.codeHistoryFeed(asOf: now)?.state(asOf: now) == .ready(Samples.codeHistory(at: now)))
    }

    @Test func aGitHubPushFillsTheInboxAndTheRuns() {
        let store = DashboardStore(config: config(), http: HTTP(userAgent: "test"), macCache: scratchCache())
        #expect(store.githubInboxFeed(asOf: now) == nil)
        #expect(store.githubActionsFeed(asOf: now) == nil)
        var push = githubPush
        push.value?.inbox = Samples.githubInbox(at: now)
        push.value?.actions = Samples.githubActions(at: now)
        store.receive(.github(push))
        #expect(store.githubInboxFeed(asOf: now)?.state(asOf: now) == .ready(Samples.githubInbox(at: now)))
        #expect(store.githubActionsFeed(asOf: now)?.state(asOf: now) == .ready(Samples.githubActions(at: now)))
    }

    /// An older Mac pushes the summary alone; the inbox waits rather than reading as empty.
    @Test func aPushWithoutTheInboxLeavesItLoading() {
        let store = DashboardStore(config: config(), http: HTTP(userAgent: "test"), macCache: scratchCache())
        store.receive(.github(githubPush))
        #expect(store.githubInboxFeed(asOf: now)?.state(asOf: now) == .loading)
        #expect(store.githubActionsFeed(asOf: now)?.state(asOf: now) == .loading)
    }

    @Test func pushesOutliveARelaunch() async throws {
        let cache = scratchCache()
        let first = DashboardStore(config: config(), http: HTTP(userAgent: "test"), macCache: cache)
        first.receive(.events(events(fetched: 10)))
        first.receive(.github(githubPush))
        await first.macCacheWrite?.value

        let second = DashboardStore(config: config(), http: HTTP(userAgent: "test"), macCache: cache)
        await second.seedPushed()
        #expect(second.pushedEvents == events(fetched: 10))
        #expect(second.pushedGitHub == githubPush)
    }

    @Test func disconnectingASourceForgetsItsValueAndItsCache() async throws {
        let cache = scratchCache()
        let store = DashboardStore(config: config(), http: HTTP(userAgent: "test"), macCache: cache)
        store.receive(.events(events(fetched: 10)))
        store.receive(.github(githubPush))
        store.receive(.disconnected(.github))
        await store.macCacheWrite?.value
        #expect(store.githubFeed(asOf: now) == nil)
        #expect(store.agenda(asOf: now) != nil)

        let relaunched = DashboardStore(config: config(), http: HTTP(userAgent: "test"), macCache: cache)
        await relaunched.seedPushed()
        #expect(relaunched.pushedGitHub == nil)
        #expect(relaunched.pushedEvents != nil)

        store.receive(.disconnected(.calendar))
        await store.macCacheWrite?.value
        #expect(store.agenda(asOf: now) == nil)
    }

    @Test func theBridgeRunsForAnAgendaOrGitHubWhenTheTVHasAKey() throws {
        var config = config()
        config.bridgeKey = SymmetricKey(size: .bits256)
        for kind in [WidgetConfig.agenda, .github] {
            let placement = try #require(Placement(config: kind, size: .medium))
            let page = try #require(Page(name: "Today", placements: [placement]))
            let dashboard = try #require(Dashboard(pages: [page]))
            #expect(Feed.needed(by: dashboard, config: config).contains(.bridge))
        }
    }
}
