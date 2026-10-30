import Foundation
import Testing
@testable import NorthlightAgent
@testable import NorthlightKit

/// The Mac's on-device model writing from the sample day. Nothing leaves the Mac:
///   BRIEFING_LIVE=1 swift test --filter BriefingLive
struct BriefingLiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["BRIEFING_LIVE"] == "1"), .timeLimit(.minutes(1)))
    func theMacsModelWritesFromTheFacts() async {
        let now = Date()
        let request = BriefingRequest(place: Samples.place, at: now, locale: "en_US", units: nil, weather: Samples.weather(at: now),
                                      events: Samples.events(at: now), alerts: [])
        print(BriefingWriter.facts(for: request))
        let briefing = await BriefingWriter.write(request)
        print(briefing)
        guard case .written(let text, _) = briefing else {
            Issue.record("the model did not write: \(briefing)")
            return
        }
        #expect(!text.isEmpty)
    }
}
