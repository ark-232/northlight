import Foundation
import Testing
@testable import NorthlightKit

@Test func theMacCountsAsGoneOnceItFallsSilent() {
    let heard = Date(timeIntervalSince1970: 1_800_000_000)
    let report = AgentReport(statuses: Samples.agents(at: heard), receivedAt: heard)
    // The Mac repeats itself every 15 s, so three missed repeats mean it is gone.
    #expect(report.statuses(asOf: heard.addingTimeInterval(44)) == Samples.agents(at: heard))
    #expect(report.statuses(asOf: heard.addingTimeInterval(46)) == nil)
}
