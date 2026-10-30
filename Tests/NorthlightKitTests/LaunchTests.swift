import Foundation
import Testing
@testable import NorthlightKit

/// Launch Library 2's next five launches, saved on 20 Oct 2026 at 04:12 UTC, when
/// the first had already flown.

@Test func upcomingLaunchesDecode() throws {
    let launches = try LaunchParsing.launches(from: fixture("launches"))
    #expect(launches.count == 5)
    let first = try #require(launches.first)
    #expect(first.mission == "Martian Moons eXploration (MMX)")
    #expect(first.rocket == "H3-24")
    #expect(first.provider == "Mitsubishi Heavy Industries")
    #expect(first.pad == "Yoshinobu Launch Complex LP-2")
    #expect(first.location == "Tanegashima Space Center, Japan")
    #expect(first.net == utc("2026-10-19T19:41:03Z"))
    #expect(first.status == "Success")
    #expect(launches[3].precision == "HR")
}

@Test func aLaunchThatHasFlownIsNoLongerNext() throws {
    let launches = try LaunchParsing.launches(from: fixture("launches"))
    let next = Launch.upcoming(launches, at: utc("2026-10-20T04:12:00Z"))
    #expect(next.first?.mission == "Bandwagon 5 (Dedicated Mid-Inclination Rideshare)")
    #expect(next.count == 4)
}

@Test func aLaunchWithNoMissionTakesItsNameAfterTheRocket() throws {
    let json = #"{"results":[{"id":"x","name":"Electron | Test Flight","status":{"abbrev":"TBD"},"net":"2026-11-01T00:00:00Z","net_precision":null,"launch_service_provider":{"name":"Rocket Lab"},"rocket":{"configuration":{"name":"Electron"}},"mission":null,"pad":{"name":"LC-1A","location":{"name":"Mahia, New Zealand"}}}]}"#
    let launch = try #require(try LaunchParsing.launches(from: Data(json.utf8)).first)
    #expect(launch.mission == "Test Flight")
    #expect(launch.precision == nil)
}

@Test func theCountdownCoarsensWithDistance() {
    #expect(Launch.countdown(2 * 86_400 + 5 * 3_600 + 59) == "T−2 d 5 h")
    #expect(Launch.countdown(6 * 3_600 + 18 * 60 + 30) == "T−6 h 18 m")
    #expect(Launch.countdown(17 * 60 + 9) == "T−17:09")
    #expect(Launch.countdown(-75) == "T+01:15")
}
