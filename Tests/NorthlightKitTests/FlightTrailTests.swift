import Foundation
import Testing
@testable import NorthlightKit

private func flight(_ id: String, _ latitude: Double?, _ longitude: Double?) -> Flight {
    Flight(id: id, label: id, type: nil, altitudeFeet: 30_000, onGround: false, groundSpeedKnots: 450,
           distanceNM: 10, track: 90, latitude: latitude, longitude: longitude)
}

private let start = Date(timeIntervalSince1970: 1_800_000_000)

@Test func eachPollAddsToAnAircraftsPath() {
    var trails = FlightTrails()
    trails.record([flight("a", 64.0, -22.0)], at: start)
    trails.record([flight("a", 64.0, -21.9)], at: start + 10)
    #expect(trails.paths["a"]?.map(\.longitude) == [-22.0, -21.9])
}

@Test func aPathReachesBackTenMinutes() {
    var trails = FlightTrails()
    for step in 0...70 {
        trails.record([flight("a", 64, -22 + Double(step) / 100)], at: start + Double(step) * 10)
    }
    #expect(trails.paths["a"]?.first?.time == start + 100)
    #expect(trails.paths["a"]?.count == 61)
}

@Test func anAircraftUnheardForTwoMinutesLeavesTheMap() {
    var trails = FlightTrails()
    trails.record([flight("a", 64, -22), flight("b", 65, -22)], at: start)
    trails.record([flight("b", 65, -21.9)], at: start + 119)
    #expect(trails.paths["a"] != nil)
    trails.record([flight("b", 65, -21.8)], at: start + 121)
    #expect(trails.paths["a"] == nil)
    #expect(trails.paths["b"]?.count == 3)
}

@Test func anAircraftWithoutAPositionDrawsNoPath() {
    var trails = FlightTrails()
    trails.record([flight("a", nil, nil)], at: start)
    #expect(trails.paths.isEmpty)
}

@Test func betweenPollsAnAircraftFliesOnAlongItsTrack() {
    // 60 knots for a minute is one nautical mile: a sixtieth of a degree of latitude,
    // and at 60 degrees north twice that in longitude.
    let fix = FlightTrails.Point(latitude: 60, longitude: -22, time: start)
    let north = fix.flown(knots: 60, track: 0, to: start + 60)
    #expect(abs(north.latitude - (60 + 1.0 / 60)) < 1e-6)
    #expect(abs(north.longitude - -22) < 1e-9)
    let east = fix.flown(knots: 60, track: 90, to: start + 60)
    #expect(abs(east.longitude - (-22 + 1.0 / 30)) < 1e-6)
}

@Test func aircraftCarryTheirPositionAndGroundStationsAreLeftOut() throws {
    let json = Data("""
    {"ac":[
      {"hex":"a1","flight":"ICE593  ","t":"B739","lat":64.2,"lon":-21.9,"alt_baro":10800,"category":"A3"},
      {"hex":"c1","flight":"OPS1","lat":63.98,"lon":-22.6,"alt_baro":"ground","category":"C2"},
      {"hex":"t1","flight":"TWR","t":"TWR","lat":64.13,"lon":-21.94,"alt_baro":"ground"}
    ]}
    """.utf8)
    let flights = try FlightParsing.flights(from: json)
    #expect(flights.map(\.id) == ["a1"])
    #expect(flights.first?.latitude == 64.2)
    #expect(flights.first?.longitude == -21.9)
}
