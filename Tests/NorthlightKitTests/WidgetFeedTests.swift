import Foundation
import Testing
@testable import NorthlightKit

private let reykjavik = Place(name: "Reykjavík", latitude: 64.1466, longitude: -21.9426,
                              timeZoneIdentifier: "Atlantic/Reykjavik", countryCode: "IS")

/// The feeds one page of `widgets` runs, at a place without NWS alerts.
private func feeds(_ widgets: [(WidgetConfig, WidgetSize)]) throws -> Set<Feed> {
    let placements = try widgets.map { try #require(Placement(config: $0.0, size: $0.1)) }
    let page = try #require(Page(name: "Page", placements: placements))
    let dashboard = try #require(Dashboard(pages: [page]))
    return Feed.needed(by: dashboard, config: Config(place: reykjavik, calendarICSURL: nil, contact: "test"))
}

@Test func spaceWeatherFetchesTheXRayHistoryOnlyForALargeWidget() throws {
    #expect(try feeds([(.spaceWeather, .small)]) == [.spaceWeather])
    #expect(try feeds([(.spaceWeather, .medium)]) == [.spaceWeather])
    #expect(try feeds([(.spaceWeather, .large)]) == [.spaceWeather, .xrays])
}

@Test func theISSWidgetRunsItsFeed() throws {
    #expect(try feeds([(.iss, .medium)]) == [.iss])
    #expect(try feeds([(.iss, .large)]) == [.iss])
}

@Test func theLaunchesWidgetRunsItsFeed() throws {
    #expect(try feeds([(.launches, .medium)]) == [.launches])
}

@Test func theHackerNewsWidgetRunsItsFeed() throws {
    #expect(try feeds([(.hackerNews, .medium), (.hackerNews, .medium)]) == [.hackerNews])
}

@Test func theStatusWidgetRunsItsFeed() throws {
    #expect(try feeds([(.serviceStatus, .small)]) == [.serviceStatus])
}

@Test func theKEVWidgetRunsItsFeed() throws {
    #expect(try feeds([(.kev, .medium)]) == [.kev])
}

@Test func theMarketsWidgetRunsCryptoAndRates() throws {
    for size in [WidgetSize.small, .medium, .large] {
        #expect(try feeds([(.markets, size)]) == [.crypto, .rates])
    }
}
