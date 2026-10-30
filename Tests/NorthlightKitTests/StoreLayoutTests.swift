import CryptoKit
import Foundation
import Testing
@testable import NorthlightKit

private let losAngeles = Place(name: "Los Angeles", latitude: 34.0522, longitude: -118.2437,
                               timeZoneIdentifier: "America/Los_Angeles", countryCode: "US")
private let reykjavik = Place(name: "Reykjavík", latitude: 64.1466, longitude: -21.9426,
                              timeZoneIdentifier: "Atlantic/Reykjavik", countryCode: "IS")
private let ics = URL(string: "https://example.com/basic.ics")!

private func config(_ place: Place, calendar: URL? = ics) -> Config {
    Config(place: place, calendarICSURL: calendar, contact: "test")
}

private func page(_ widgets: [(WidgetConfig, WidgetSize)]) throws -> Dashboard {
    let placements = try widgets.map { try #require(Placement(config: $0.0, size: $0.1)) }
    let page = try #require(Page(name: "Page", placements: placements))
    return try #require(Dashboard(pages: [page]))
}

@Test func theStarterLayoutRunsEveryFeedItShows() {
    #expect(Feed.needed(by: .starter, config: config(losAngeles)) ==
            [.weather, .alerts, .aurora, .calendar(ics: ics, icloud: nil), .airQuality, .flights, .quakes(minMagnitude: 2.5)])
}

@Test func computedWidgetsFetchNothingButTheHeadersAlerts() throws {
    let daylight = try page([(.daylight, .small)])
    #expect(Feed.needed(by: daylight, config: config(losAngeles)) == [.alerts])
    #expect(Feed.needed(by: daylight, config: config(reykjavik)).isEmpty)
}

@Test func anAgendaWithoutACalendarFetchesNothing() throws {
    let agenda = try page([(.agenda, .medium)])
    #expect(Feed.needed(by: agenda, config: config(reykjavik, calendar: nil)).isEmpty)
}

@Test func quakesComeFromTheLowerFloorButNeverBelowWhatThePlaceCatalogs() throws {
    let two = try page([(.seismic(minMagnitude: 3.0), .medium), (.seismic(minMagnitude: 4.0), .medium)])
    #expect(Feed.needed(by: two, config: config(losAngeles)).contains(.quakes(minMagnitude: 3.0)))
    #expect(Feed.needed(by: two, config: config(reykjavik)).contains(.quakes(minMagnitude: 4.5)))
}

@Test func gitHubRunsOnlyOnceAnAccountIsConnected() throws {
    let github = try page([(.github, .medium)])
    var connected = config(reykjavik)
    connected.githubToken = "gho_test"
    #expect(Feed.needed(by: github, config: config(reykjavik)).isEmpty)
    #expect(Feed.needed(by: github, config: connected) == [.github(token: "gho_test")])
}

/// Lines, contributions and Actions read the summary; Actions and the inbox have
/// feeds of their own.
@Test func theGitHubFamilyRunsTheFeedsItReads() throws {
    var connected = config(reykjavik)
    connected.githubToken = "gho_test"
    let summary = Feed.github(token: "gho_test")
    for (kind, feeds) in [(WidgetConfig.githubLines, [summary]), (.githubCommits, [summary]),
                          (.githubInbox, [.githubInbox(token: "gho_test")]),
                          (.githubActions, [summary, .githubActions(token: "gho_test")])] {
        let dashboard = try page([(kind, .medium)])
        #expect(Feed.needed(by: dashboard, config: connected) == Set(feeds))
        #expect(Feed.needed(by: dashboard, config: config(reykjavik)).isEmpty)
    }
}

@Test func agentsAndTheBriefingListenOnTheBridgeOnlyWithAKey() throws {
    let agents = try page([(.agents, .medium)]), briefing = try page([(.briefing, .medium)])
    var keyed = config(reykjavik)
    keyed.bridgeKey = SymmetricKey(size: .bits256)
    #expect(Feed.needed(by: agents, config: config(reykjavik)).isEmpty)
    #expect(Feed.needed(by: agents, config: keyed) == [.bridge])
    #expect(Feed.needed(by: briefing, config: keyed) == [.bridge])
}

@Test func theBridgeListensForTheMacsEditorWhateverThePageHolds() throws {
    let network = try page([(.network, .small)])
    var keyed = config(reykjavik)
    keyed.bridgeKey = SymmetricKey(size: .bits256)
    #expect(Feed.needed(by: network, config: keyed) == [.network, .bridge])
}

/// Whether aurora is live depends on the cloud cover, which comes with the weather.
@Test func anAuroraWidgetAlsoReadsTheWeather() throws {
    let aurora = try page([(.aurora, .small)])
    #expect(Feed.needed(by: aurora, config: config(reykjavik)) == [.aurora, .weather])
}

@Test func aNetworkWidgetWatchesTheConnection() throws {
    let network = try page([(.network, .small)])
    #expect(Feed.needed(by: network, config: config(reykjavik)) == [.network])
}

@Test func anAgendaReadsTheICSAddressAndTheChosenICloudCalendarsTogether() throws {
    let agenda = try page([(.agenda, .medium)])
    let home = CalDAV.Calendar(url: URL(string: "https://p42-caldav.icloud.com/1/calendars/home/")!, name: "Home")
    var both = config(reykjavik)
    both.icloud = ICloudAccount(appleID: "someone@icloud.com", password: "abcd-efgh-ijkl-mnop", calendars: [home])
    #expect(Feed.needed(by: agenda, config: both) == [.calendar(ics: ics, icloud: both.icloud)])

    // An account with no calendars chosen adds nothing to read.
    var none = config(reykjavik, calendar: nil)
    none.icloud = ICloudAccount(appleID: "someone@icloud.com", password: "abcd-efgh-ijkl-mnop", calendars: [])
    #expect(Feed.needed(by: agenda, config: none).isEmpty)
}
