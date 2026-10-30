import Foundation
import Testing
@testable import NorthlightKit

/// wheretheiss.at's answer for the ISS, saved on 20 Oct 2026.

@Test func theStationsPositionDecodes() throws {
    let fix = try ISSParsing.fix(from: fixture("iss"))
    #expect(abs(fix.latitude - -4.8814) < 0.0001)
    #expect(abs(fix.longitude - 132.6814) < 0.0001)
    #expect(abs(fix.altitudeKM - 422.05) < 0.01)
    #expect(abs(fix.velocityKMH - 27_570.9) < 0.1)
    #expect(fix.sunlit)
    #expect(fix.time == Date(timeIntervalSince1970: 1_792_469_782))
}

@Test func anEclipsedStationIsNotSunlit() throws {
    let json = #"{"latitude":1,"longitude":2,"altitude":420,"velocity":27600,"visibility":"eclipsed","timestamp":1792469782}"#
    #expect(try ISSParsing.fix(from: Data(json.utf8)).sunlit == false)
}

private func fix(_ seconds: TimeInterval, lon: Double) -> ISSFix {
    ISSFix(latitude: 0, longitude: lon, altitudeKM: 420, velocityKMH: 27_600, sunlit: true,
           time: Date(timeIntervalSince1970: seconds))
}

@Test func theTrackKeepsAnOrbitAndSkipsRepeats() {
    var track = ISSTrack()
    for step in 0..<700 {
        track = track.adding(fix(Double(step) * 10, lon: -180 + Double(step % 360)))
    }
    track = track.adding(fix(6_990, lon: 0))
    #expect(track.fixes.count == Int(ISSTrack.span) / 10 + 1)
    #expect(track.fixes.first?.time == Date(timeIntervalSince1970: 6_990 - ISSTrack.span))
    #expect(track.latest?.time == Date(timeIntervalSince1970: 6_990))
}

@Test func theTrackBreaksAtTheDateLineAndAtGaps() {
    let track = [fix(0, lon: 170), fix(10, lon: 175), fix(20, lon: -179), fix(30, lon: -175),
                 fix(400, lon: -150), fix(410, lon: -148)]
        .reduce(ISSTrack()) { $0.adding($1) }
    #expect(track.segments.map { $0.map(\.longitude) } == [[170, 175], [-179, -175], [-150, -148]])
}
