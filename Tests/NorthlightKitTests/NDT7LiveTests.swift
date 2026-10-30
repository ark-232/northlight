import Foundation
import Testing
@testable import NorthlightKit

/// A real test against M-Lab, which publishes this machine's public IP address, the time
/// and the results as open data. Run it only with that understood:
///   NDT7_LIVE=1 swift test --filter NDT7Live
struct NDT7LiveTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["NDT7_LIVE"] == "1"), .timeLimit(.minutes(1)))
    func aLiveTestMeasuresBothDirections() async throws {
        let http = HTTP(userAgent: "Northlight/0.1.0 (swift test)")
        let result = try await http.speedTest(on: try await http.nearestNDT7Server(clientVersion: "0.1.0"))
        print("ndt7 \(result.server): down \(result.downloadMegabits) Mbps, up \(result.uploadMegabits) Mbps,",
              "idle \(result.idleLatency) ms, loaded \(result.loadedLatency) ms, \(Int(result.rpm)) RPM, \(result.responsiveness)")
        #expect(result.downloadMegabits > 0)
        #expect(result.uploadMegabits > 0)
    }
}
