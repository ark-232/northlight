import Foundation
import Testing
@testable import NorthlightKit

/// Statuspage summaries for GitHub and Claude, saved on 20 Oct 2026 with nothing
/// wrong; the incident cases are trimmed from Statuspage's documented shape.

@Test func aQuietPageReadsOperational() throws {
    let github = try ServiceStatusParsing.status(of: "GitHub", from: fixture("status-gh"))
    #expect(github == ServiceStatus(service: "GitHub", indicator: .none, summary: "All Systems Operational", incident: nil))
    let claude = try ServiceStatusParsing.status(of: "Claude", from: fixture("status-claude"))
    #expect(claude.indicator == .none)
    #expect(claude.incident == nil)
}

@Test func anOpenIncidentIsNamed() throws {
    let json = #"{"status":{"indicator":"major","description":"Partial System Outage"},"incidents":[{"name":"Elevated errors on Claude Opus","status":"investigating","impact":"major"}]}"#
    let status = try ServiceStatusParsing.status(of: "Claude", from: Data(json.utf8))
    #expect(status.indicator == .major)
    #expect(status.summary == "Partial System Outage")
    #expect(status.incident == "Elevated errors on Claude Opus")
}

@Test func anIndicatorStatuspageAddsLaterReadsAsUnknown() throws {
    let json = #"{"status":{"indicator":"degraded","description":"Something new"},"incidents":[]}"#
    #expect(try ServiceStatusParsing.status(of: "GitHub", from: Data(json.utf8)).indicator == .unknown)
}
