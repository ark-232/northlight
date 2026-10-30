import Foundation
import Testing
@testable import NorthlightKit

// MARK: - Moon

/// Checked against published new/full moon times for 2026.
@Test func moonIsNewAtTheKnownEpoch() {
    let moon = Moon(date: Moon.referenceNewMoon)
    #expect(moon.name == "New moon")
    #expect(moon.illumination < 0.01)
}

@Test func moonIsFullHalfACycleLater() {
    let half = Moon.referenceNewMoon.addingTimeInterval(Moon.synodicMonth * 86_400 / 2)
    let moon = Moon(date: half)
    #expect(moon.name == "Full moon")
    #expect(moon.illumination > 0.99)
}

@Test func moonQuartersAreHalfLit() {
    let quarter = Moon.referenceNewMoon.addingTimeInterval(Moon.synodicMonth * 86_400 / 4)
    let moon = Moon(date: quarter)
    #expect(moon.name == "First quarter")
    #expect(abs(moon.illumination - 0.5) < 0.02)
}

@Test func moonPhaseStaysInRangeAcrossManyCycles() {
    // Walk two years in six-hour steps; nothing may fall outside the domain.
    for step in stride(from: 0.0, to: 730 * 24, by: 6) {
        let moon = Moon(date: Moon.referenceNewMoon.addingTimeInterval(step * 3_600))
        #expect(moon.age >= 0 && moon.age < Moon.synodicMonth)
        #expect(moon.illumination >= 0 && moon.illumination <= 1)
        #expect(!moon.name.isEmpty)
    }
}

@Test func moonWorksBeforeTheEpoch() {
    let past = Moon.referenceNewMoon.addingTimeInterval(-100 * 86_400)
    let moon = Moon(date: past)
    #expect(moon.age >= 0 && moon.age < Moon.synodicMonth)
    #expect(moon.illumination >= 0 && moon.illumination <= 1)
}

// MARK: - Duration formatting

@Test func daylightFormatsAsHoursAndMinutes() {
    // A live value from 18 Oct 2026.
    #expect(Double(35_252.77).hoursMinutes == "9h 47m")
    #expect(Double(0).hoursMinutes == "0h 0m")
    #expect(Double(86_399).hoursMinutes == "23h 59m")
}

@Test func daylightChangeIsSigned() {
    // Losing about five and three-quarter minutes a day in mid-October.
    #expect(Double(-341.69).signedMinutesSeconds == "−5m 42s")
    #expect(Double(120).signedMinutesSeconds == "+2m 0s")
    #expect(Double(-30).signedMinutesSeconds == "−30s")
}

// MARK: - ADS-B

/// `alt_baro` is a number in flight and the string "ground" on the ground. A
/// plain Int decoder would throw on the second form and drop the whole payload.
@Test func altBaroAcceptsBothNumberAndGroundString() throws {
    let json = """
    {"ac":[
      {"hex":"a1b2c3","flight":"ASA123 ","t":"B738","alt_baro":34000,"gs":430.2,"dst":12.4,"track":180},
      {"hex":"d4e5f6","r":"N12345","t":"C172","alt_baro":"ground","gs":0,"dst":3.1}
    ]}
    """.data(using: .utf8)!

    let flights = try FlightParsing.flights(from: json)
    #expect(flights.count == 2)

    // Airborne sorts ahead of ground regardless of distance.
    #expect(flights[0].label == "ASA123")
    #expect(flights[0].altitudeFeet == 34_000)
    #expect(flights[0].onGround == false)

    #expect(flights[1].label == "N12345")
    #expect(flights[1].altitudeFeet == nil)
    #expect(flights[1].onGround == true)
}

@Test func flightLabelFallsBackThroughCallsignRegistrationHex() throws {
    let json = """
    {"ac":[
      {"hex":"aaa111","alt_baro":5000,"dst":1},
      {"hex":"bbb222","r":"N777AB","alt_baro":6000,"dst":2},
      {"hex":"ccc333","flight":"UAL99","r":"N999","alt_baro":7000,"dst":3}
    ]}
    """.data(using: .utf8)!

    let labels = try FlightParsing.flights(from: json).map(\.label)
    #expect(labels == ["aaa111", "N777AB", "UAL99"])
}

@Test func airborneFlightsSortNearestFirst() throws {
    let json = """
    {"ac":[
      {"hex":"a","alt_baro":10000,"dst":40},
      {"hex":"b","alt_baro":10000,"dst":5},
      {"hex":"c","alt_baro":10000,"dst":20}
    ]}
    """.data(using: .utf8)!
    #expect(try FlightParsing.flights(from: json).map(\.label) == ["b", "c", "a"])
}

@Test func aSquawkCodeIsKept() throws {
    let json = """
    {"ac":[{"hex":"a","flight":"ICE123","alt_baro":12000,"dst":8,"squawk":"7700"},{"hex":"b","alt_baro":9000,"dst":9}]}
    """.data(using: .utf8)!
    #expect(try FlightParsing.flights(from: json).map(\.squawk) == ["7700", nil])
}

@Test func emptyAircraftListIsNormalNotAnError() throws {
    #expect(try FlightParsing.flights(from: Data(#"{"ac":[]}"#.utf8)).isEmpty)
    // adsb.lol omits `ac` entirely when it has heard nothing.
    #expect(try FlightParsing.flights(from: Data("{}".utf8)).isEmpty)
}

@Test func garbageAdsbPayloadThrows() {
    #expect(throws: (any Error).self) {
        _ = try FlightParsing.flights(from: Data("not json".utf8))
    }
}

// MARK: - Air quality

@Test func aqiBandsFollowTheEPALadder() {
    #expect(AirQuality(usAQI: 39, pm25: 6.1, pm10: 6.7).band.label == "Good")
    #expect(AirQuality(usAQI: 75, pm25: nil, pm10: nil).band.label == "Moderate")
    #expect(AirQuality(usAQI: 160, pm25: nil, pm10: nil).band.label == "Unhealthy")
    #expect(AirQuality(usAQI: 400, pm25: nil, pm10: nil).band.rank == 5)
    #expect(AirQuality(usAQI: nil, pm25: nil, pm10: nil).band.label == "—")
}
