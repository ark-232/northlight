import Foundation
import Testing
@testable import NorthlightKit

// Shapes from M-Lab's Locate v2 and the ndt7 protocol spec (v0.11.0), as of 19 Oct 2026.

private let locate = """
{"results":[{"machine":"mlab1-sea09.mlab-oti.measurement-lab.org","hostname":"ndt-mlab1-sea09.mlab-oti.measurement-lab.org",
  "location":{"city":"Seattle","country":"US"},
  "urls":{"ws:///ndt/v7/download":"ws://ndt-mlab1-sea09.mlab-oti.measurement-lab.org/ndt/v7/download?access_token=down",
          "ws:///ndt/v7/upload":"ws://ndt-mlab1-sea09.mlab-oti.measurement-lab.org/ndt/v7/upload?access_token=up",
          "wss:///ndt/v7/download":"wss://ndt-mlab1-sea09.mlab-oti.measurement-lab.org/ndt/v7/download?access_token=down",
          "wss:///ndt/v7/upload":"wss://ndt-mlab1-sea09.mlab-oti.measurement-lab.org/ndt/v7/upload?access_token=up"}}]}
"""

/// A server measurement `seconds` into a test.
private func measurement(seconds: Double, rtt: Int64 = 20_000, minRTT: Int64 = 9_000, received: Int64 = 0) -> NDT7.Measurement {
    NDT7.Measurement(tcpInfo: .init(elapsedTime: Int64(seconds * 1_000_000), minRTT: minRTT, rtt: rtt, bytesReceived: received))
}

struct NDT7Tests {
    @Test func theNearestServerComesFromLocateOverTLSWithTheDownloadCappedAt250MB() throws {
        let server = try NDT7.server(fromLocate: Data(locate.utf8))
        #expect(server.name == "Seattle, US")
        #expect(server.download.absoluteString ==
                "wss://ndt-mlab1-sea09.mlab-oti.measurement-lab.org/ndt/v7/download?access_token=down&early_exit=250")
        #expect(server.upload.absoluteString == "wss://ndt-mlab1-sea09.mlab-oti.measurement-lab.org/ndt/v7/upload?access_token=up")
    }

    @Test func noServerIsAnErrorThatSaysSo() {
        #expect(throws: FeedError.self) { try NDT7.server(fromLocate: Data(#"{"results":[]}"#.utf8)) }
    }

    @Test func aServerMessageDecodesItsTCPInfoInMicroseconds() throws {
        let text = """
        {"ConnectionInfo":{"Client":"192.0.2.1:5678","Server":"[2001:db8::1]:443","UUID":"x"},"Origin":"server","Test":"upload",
         "TCPInfo":{"BusyTime":10000,"BytesAcked":100,"BytesReceived":12500000,"BytesSent":120,"ElapsedTime":10000000,
                    "MinRTT":9000,"RTT":15000,"RTTVar":2000}}
        """
        #expect(try NDT7.measurement(from: text) == measurement(seconds: 10, rtt: 15_000, minRTT: 9_000, received: 12_500_000))
    }

    @Test func downloadSpeedIsTheBytesReceivedOverTheTime() {
        #expect(NDT7.megabits(bytes: 125_000_000, seconds: 10) == 100)
    }

    /// ndt-server reports no AppInfo, so the upload is what the server says it received.
    @Test func uploadSpeedIsTheServersOwnCount() {
        let messages = [measurement(seconds: 5, received: 5_000_000), measurement(seconds: 10, received: 12_500_000)]
        #expect(NDT7.uploadMegabits(from: messages) == 10)
        #expect(NDT7.uploadMegabits(from: []) == nil)
    }

    @Test func idleLatencyIsTheLeastRoundTrip() {
        let messages = [measurement(seconds: 1, minRTT: 12_000), measurement(seconds: 2, minRTT: 9_500), measurement(seconds: 3, minRTT: 11_000)]
        #expect(NDT7.idleLatency(from: messages) == 9.5)
    }

    @Test func loadedLatencyIsATrimmedMeanOfTheRoundTripsAfterThreeSeconds() {
        // Ramp-up samples before 3 s are left out, and the slowest 5 % is trimmed.
        let rampUp = [measurement(seconds: 1, rtt: 900_000), measurement(seconds: 2.9, rtt: 900_000)]
        let loaded = (0..<19).map { measurement(seconds: 3 + Double($0) * 0.25, rtt: 40_000) }
        let spike = measurement(seconds: 8, rtt: 2_000_000)
        #expect(NDT7.loadedLatency(from: rampUp + loaded + [spike]) == 40)
        // A fast link reaches the 250 MB cap before three seconds; every sample counts then.
        #expect(NDT7.loadedLatency(from: rampUp) == 900)
        #expect(NDT7.loadedLatency(from: []) == nil)
    }

    @Test func uploadMessagesDoubleWhileUnderASixteenthOfTheBytesSentUpToOneMebibyte() {
        #expect(NDT7.nextMessageSize(after: 8_192, sent: 16 * 8_192) == 8_192)
        #expect(NDT7.nextMessageSize(after: 8_192, sent: 16 * 8_192 + 16) == 16_384)
        #expect(NDT7.nextMessageSize(after: 1 << 20, sent: 1 << 40) == 1 << 20)
    }

    @Test func responsivenessTiersFollowTheDraft() {
        func tier(_ latency: Double) -> SpeedResult.Responsiveness {
            SpeedResult(date: .now, server: "", downloadMegabits: 0, uploadMegabits: 0, idleLatency: 0, loadedLatency: latency).responsiveness
        }
        #expect(tier(200) == .poor)         // 300 RPM or worse
        #expect(tier(199) == .fair)
        #expect(tier(60.1) == .fair)
        #expect(tier(60) == .good)          // 1000 RPM
        #expect(tier(10.1) == .good)
        #expect(tier(10) == .excellent)     // 6000 RPM or better
    }
}

struct MeteredSpeedTestTests {
    /// URLSession refuses a metered link with "offline" and no reason, so the path says it first.
    @Test func aMeteredLinkRefusesTheTestAndSaysWhy() {
        #expect(NetworkPath(link: .wifi, quality: nil, isMetered: true).speedTestRefusal
                == "This network is metered or in Low Data Mode. Speed tests run on unmetered networks only.")
        #expect(NetworkPath(link: .ethernet, quality: .good).speedTestRefusal == nil)
    }
}
