import Foundation
import Testing
@testable import NorthlightKit

/// These lock in the payload shapes observed live on 18 Oct 2026. SWPC changed
/// the K-index product's shape at least once already, so the current form and the
/// historical one are both asserted.

@Test func kpParsesCurrentObjectForm() throws {
    let json = """
    [{"time_tag":"2026-10-12T00:00:00","Kp":1.67,"a_running":6,"station_count":8},
     {"time_tag":"2026-10-18T21:00:00","Kp":0.33,"a_running":2,"station_count":8}]
    """.data(using: .utf8)!

    let reading = try AuroraParsing.kp(from: json)
    #expect(reading.kp == 0.33)

    let observed = try #require(reading.observed)
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC")!
    #expect(utc.component(.hour, from: observed) == 21)
    #expect(utc.component(.day, from: observed) == 18)
}

@Test func kpFallsBackToLegacyStringArrayForm() throws {
    let json = """
    [["time_tag","Kp","a_running","station_count"],
     ["2026-10-18 18:00:00","4.33","20","8"]]
    """.data(using: .utf8)!

    let reading = try AuroraParsing.kp(from: json)
    #expect(reading.kp == 4.33)
    #expect(reading.observed != nil)
}

@Test func kpToleratesQuotedNumbers() throws {
    let json = #"[{"time_tag":"2026-10-18T21:00:00","Kp":"5.00"}]"#.data(using: .utf8)!
    #expect(try AuroraParsing.kp(from: json).kp == 5.0)
}

@Test func kpRejectsGarbageRatherThanReportingZero() {
    #expect(throws: (any Error).self) {
        _ = try AuroraParsing.kp(from: Data("[]".utf8))
    }
    #expect(throws: (any Error).self) {
        _ = try AuroraParsing.kp(from: Data("{\"nope\":1}".utf8))
    }
}

@Test func ovationPicksNearestGridCell() {
    // Grid is whole degrees, longitude 0–359. Reykjavík is lat 64.15, lon -21.94,
    // which is 338.06 east.
    let json = """
    {"Observation Time":"2026-10-19T02:39:00Z",
     "Forecast Time":"2026-10-19T03:49:00Z",
     "coordinates":[[0,-90,1],[337,64,12],[338,64,44],[339,64,13],[338,75,99]]}
    """.data(using: .utf8)!

    let result = AuroraParsing.localProbability(from: json, lat: 64.1466, lon: -21.9426)
    #expect(result.probability == 44)
    #expect(result.forecastTime != nil)
}

@Test func ovationFailureIsSoftSoKpSurvives() {
    let result = AuroraParsing.localProbability(from: Data("not json".utf8), lat: 64.15, lon: -21.94)
    #expect(result.probability == nil)
    #expect(result.forecastTime == nil)
}

@Test func ovationReturnsNilWhenNoCellIsNearby() {
    let json = #"{"coordinates":[[0,-90,50],[100,20,90]]}"#.data(using: .utf8)!
    let result = AuroraParsing.localProbability(from: json, lat: 64.15, lon: -21.94)
    #expect(result.probability == nil)
}

@Test func auroraActivityLabelsTrackTheKpLadder() {
    #expect(Aurora(kp: 0.33, kpObserved: nil, localProbability: nil, forecastTime: nil).activityLabel == "Quiet")
    #expect(Aurora(kp: 4.0, kpObserved: nil, localProbability: nil, forecastTime: nil).activityLabel == "Minor storm")
    #expect(Aurora(kp: 8.5, kpObserved: nil, localProbability: nil, forecastTime: nil).activityLabel == "Extreme storm")
}

@Test func shortAgeFormatsAcrossScales() {
    #expect(TimeInterval(42).shortAge == "42s")
    #expect(TimeInterval(600).shortAge == "10m")
    #expect(TimeInterval(7_200).shortAge == "2h")
    #expect(TimeInterval(172_800).shortAge == "2d")
}

@Test func theCurrentCloudCoverIsRead() throws {
    let json = Data("""
    {"current":{"temperature_2m":1,"apparent_temperature":-2,"weather_code":3,"wind_speed_10m":10,
                "wind_direction_10m":180,"relative_humidity_2m":80,"is_day":0,"cloud_cover":87},
     "daily":{"time":[],"temperature_2m_max":[],"temperature_2m_min":[],"weather_code":[],
              "precipitation_probability_max":[],"snowfall_sum":[]}}
    """.utf8)
    #expect(try WeatherParsing.weather(from: json, timeZone: .gmt).cloudCover == 87)
}

@Test func theRecordedWeatherDecodesDayByDayInThePlacesZone() throws {
    let url = try #require(Bundle.module.url(forResource: "open-meteo", withExtension: "json", subdirectory: "Fixtures"))
    let zone = TimeZone(identifier: "Atlantic/Reykjavik")!
    let weather = try WeatherParsing.weather(from: Data(contentsOf: url), timeZone: zone)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    #expect(weather.days.first?.date == calendar.date(from: DateComponents(year: 2026, month: 10, day: 19)))
    #expect(weather.days.map(\.precipitationChance) == [27, 33, 12, 22, 31, 64, 20])
    #expect(weather.days.map(\.code) == [71, 85, 71, 71, 71, 85, 3])
    #expect(weather.isDay == false)
}

// MARK: - USGS

/// GeoJSON orders a point longitude, latitude, depth.
@Test func quakesKeepTheirCoordinatesInGeoJSONOrder() throws {
    let json = """
    {"features":[{"id":"us7000r1","properties":{"mag":4.2,"place":"12 km SW of Grindavík, Iceland","time":1760900000000},
      "geometry":{"type":"Point","coordinates":[-22.6,63.8,95.4]}}]}
    """.data(using: .utf8)!

    let quake = try #require(try QuakeParsing.quakes(from: json).first)
    #expect(quake.latitude == 63.8)
    #expect(quake.longitude == -22.6)
    #expect(quake.depthKm == 95.4)
    #expect(quake.magnitude == 4.2)
}
