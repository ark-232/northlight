import Foundation
import Network
import Testing
@testable import NorthlightKit

/// A TCP listener on loopback that takes every connection and drops it.
private func listen() async throws -> NWListener {
    let listener = try NWListener(using: .tcp, on: .any)
    listener.newConnectionHandler = { $0.cancel() }
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
        listener.stateUpdateHandler = { state in
            switch state {
            case .ready: continuation.resume()
            case .failed(let error): continuation.resume(throwing: error)
            default: break
            }
        }
        listener.start(queue: DispatchQueue(label: "latency-listener"))
    }
    return listener
}

@Test(.timeLimit(.minutes(1)))
func aConnectToAListeningPortAnswersWithItsRoundTrip() async throws {
    let listener = try await listen()
    defer { listener.cancel() }
    let rtt = await LatencyMonitor.probe(host: "127.0.0.1", port: listener.port!.rawValue)
    #expect(rtt.map { $0 >= 0 && $0 < 1_000 } == true)
}

/// A gateway with no web server answers the connect with a reset: a round trip all the same.
@Test(.timeLimit(.minutes(1)))
func aRefusedConnectIsAnAnswer() async throws {
    let listener = try await listen()
    let port = listener.port!.rawValue
    listener.cancel()
    try await Task.sleep(for: .milliseconds(100))
    let rtt = await LatencyMonitor.probe(host: "127.0.0.1", port: port)
    #expect(rtt.map { $0 >= 0 && $0 < 1_000 } == true)
}

@Test(.timeLimit(.minutes(1)))
func aConnectNothingAnswersFailsByItsTimeout() async {
    let clock = ContinuousClock()
    let began = clock.now
    // TEST-NET-1, which nothing routes.
    #expect(await LatencyMonitor.probe(host: "192.0.2.1", port: 443, timeout: 0.5) == nil)
    #expect(began.duration(to: clock.now) < .seconds(3))
}
