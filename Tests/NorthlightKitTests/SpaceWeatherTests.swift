import Foundation
import Testing
@testable import NorthlightKit

/// SWPC responses saved on 20 Oct 2026 between 04:12 and 04:45 UTC. The solar
/// wind comes from SWPC's one-reading summaries, rounded to whole numbers.

@Test func solarWindComesFromTheSummaries() throws {
    let wind = try SpaceWeatherParsing.wind(speed: fixture("swpc-wind-speed"), field: fixture("swpc-wind-field"))
    #expect(wind.speed == 324)
    #expect(wind.bz == 0)
    #expect(wind.at == utc("2026-10-20T04:45:00Z"))
}

@Test func aSouthwardFieldKeepsItsSign() throws {
    let speed = Data(#"[{"proton_speed": 612, "time_tag": "2026-10-20T04:45:00Z"}]"#.utf8)
    let field = Data(#"[{"bt": 14, "bz_gsm": -11, "time_tag": "2026-10-20T04:46:00Z"}]"#.utf8)
    let wind = try SpaceWeatherParsing.wind(speed: speed, field: field)
    #expect(wind.speed == 612)
    #expect(wind.bz == -11)
    #expect(wind.at == utc("2026-10-20T04:46:00Z"))
}

@Test func theCurrentClassComesFromTheFlareFile() throws {
    #expect(try SpaceWeatherParsing.currentClass(from: fixture("swpc-flares")) == "B5.6")
}

@Test func xraysKeepTheLongChannelInTimeOrder() throws {
    let xrays = try SpaceWeatherParsing.xrays(from: fixture("swpc-xrays"))
    #expect(xrays.count == 30)
    #expect(xrays.first?.time == utc("2026-10-20T03:43:00Z"))
    #expect(xrays.last?.time == utc("2026-10-20T04:12:00Z"))
    #expect(xrays.map(\.time) == xrays.map(\.time).sorted())
    #expect(SpaceWeather.flareClass(flux: try #require(xrays.last).flux) == "B5.6")
}

@Test func theFlareClassIsTheLetterForTheDecadeAndTheMultiplier() {
    #expect(SpaceWeather.flareClass(flux: 3e-9) == "A0.3")
    #expect(SpaceWeather.flareClass(flux: 2.664e-6) == "C2.7")
    #expect(SpaceWeather.flareClass(flux: 1e-5) == "M1.0")
    // Rounding up to ten moves to the next letter rather than printing B10.0.
    #expect(SpaceWeather.flareClass(flux: 9.97e-7) == "C1.0")
    // X has no letter above it.
    #expect(SpaceWeather.flareClass(flux: 1.23e-3) == "X12.3")
}

@Test func theLatestFlareReadsItsPeak() throws {
    let flare = try #require(try SpaceWeatherParsing.flare(from: fixture("swpc-flares")))
    #expect(flare.peakClass == "C2.6")
    #expect(flare.peak == utc("2026-10-20T03:03:00Z"))
    #expect(flare.end == utc("2026-10-20T03:08:00Z"))
}

@Test func theScalesAreTodaysObservedLevels() throws {
    #expect(try SpaceWeatherParsing.scales(from: fixture("swpc-scales")) == SpaceWeather.Scales(r: 0, s: 0, g: 0))
    let storm = Data(#"{"0":{"R":{"Scale":"1"},"S":{"Scale":null},"G":{"Scale":"3"}},"1":{"R":{"Scale":null},"S":{"Scale":null},"G":{"Scale":"4"}}}"#.utf8)
    #expect(try SpaceWeatherParsing.scales(from: storm) == SpaceWeather.Scales(r: 1, s: 0, g: 3))
}
