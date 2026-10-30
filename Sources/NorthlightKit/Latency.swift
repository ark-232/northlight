import Foundation
import Network

/// One probe's round trip.
public struct LatencySample: Codable, Equatable, Sendable {
    public var date: Date
    /// Nil when the connect timed out or failed.
    public var milliseconds: Double?

    public init(date: Date, milliseconds: Double?) {
        self.date = date
        self.milliseconds = milliseconds
    }
}

/// The last six hours of probes from this Apple TV, 30 s apart: to the internet and to
/// the gateway.
public struct LatencyHistory: Codable, Equatable, Sendable {
    public enum Target: Sendable { case internet, gateway }

    public static let capacity = 720

    public private(set) var internet: [LatencySample] = []
    public private(set) var gateway: [LatencySample] = []

    public init() {}

    public mutating func record(_ sample: LatencySample, to target: Target) {
        switch target {
        case .internet: internet = Array((internet + [sample]).suffix(Self.capacity))
        case .gateway: gateway = Array((gateway + [sample]).suffix(Self.capacity))
        }
    }

    /// A new network has a new gateway.
    public mutating func clearGateway() {
        gateway = []
    }

    /// A gateway that filters its ports never answers, so after five silent probes its hop
    /// hides rather than reading as down.
    public var gatewayHidden: Bool {
        gateway.count >= 5 && gateway.allSatisfy { $0.milliseconds == nil }
    }

    /// The answered stretches, for a line with gaps: a run ends at a failure or where
    /// nothing ran for longer than three probes.
    public static func runs(_ samples: [LatencySample], gap: TimeInterval = 90) -> [[LatencySample]] {
        var runs: [[LatencySample]] = []
        var current: [LatencySample] = []
        for sample in samples {
            if sample.milliseconds == nil || current.last.map({ sample.date.timeIntervalSince($0.date) > gap }) == true {
                if !current.isEmpty { runs.append(current) }
                current = []
            }
            if sample.milliseconds != nil { current.append(sample) }
        }
        if !current.isEmpty { runs.append(current) }
        return runs
    }
}

public struct LatencyStats: Equatable, Sendable {
    public var median: Double?
    /// The mean change from one answer to the next.
    public var jitter: Double?
    public var failed: Int
    /// The oldest probe counted.
    public var since: Date?

    public init(_ samples: [LatencySample]) {
        let answers = samples.compactMap(\.milliseconds)
        let sorted = answers.sorted()
        median = sorted.isEmpty ? nil
            : sorted.count.isMultiple(of: 2) ? (sorted[sorted.count / 2 - 1] + sorted[sorted.count / 2]) / 2
            : sorted[sorted.count / 2]
        let changes = zip(answers, answers.dropFirst()).map { abs($1 - $0) }
        jitter = changes.isEmpty ? nil : changes.reduce(0, +) / Double(changes.count)
        failed = samples.count - answers.count
        since = samples.first?.date
    }
}

/// How a round trip reads. The gateway is on the LAN, so it is held to tighter marks.
public enum LatencyGrade: Sendable {
    case good, fair, poor

    public init(milliseconds: Double, onLAN: Bool) {
        let (good, fair): (Double, Double) = onLAN ? (5, 20) : (30, 100)
        self = milliseconds < good ? .good : milliseconds < fair ? .fair : .poor
    }
}

/// TCP connects without TLS, about 200 bytes each, timed to the answer.
public enum LatencyMonitor {
    public static let interval: Duration = .seconds(30)
    public static let internetHost = "api.github.com"

    /// The round trip of one connect to `host`, in milliseconds: the handshake's own
    /// round trip when the connection opens, and the time to the reset when it is
    /// refused, since a refusal is an answer too. Nil after `timeout` seconds or any
    /// other failure.
    public static func probe(host: String, port: UInt16, timeout: TimeInterval = 3) async -> Double? {
        let attempt = Attempt(NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp))
        return await withTaskCancellationHandler {
            await attempt.run(timeout: timeout)
        } onCancel: {
            attempt.cancel()
        }
    }

    /// The gateway on 443, else 80.
    public static func probeGateway(_ host: String) async -> Double? {
        if let rtt = await probe(host: host, port: 443) { return rtt }
        return await probe(host: host, port: 80)
    }

    /// Everything runs on its own queue, which is what makes it safe to share.
    private final class Attempt: @unchecked Sendable {
        private let connection: NWConnection
        private let queue = DispatchQueue(label: "northlight.latency")
        private var continuation: CheckedContinuation<Double?, Never>?
        private var began = DispatchTime.now()
        private var done = false

        init(_ connection: NWConnection) {
            self.connection = connection
        }

        func run(timeout: TimeInterval) async -> Double? {
            await withCheckedContinuation { continuation in
                queue.async { [self] in
                    guard !done else { return continuation.resume(returning: nil) }
                    self.continuation = continuation
                    began = .now()
                    connection.stateUpdateHandler = { [self] state in
                        switch state {
                        case .ready:
                            let elapsed = self.elapsed
                            connection.requestEstablishmentReport(queue: queue) { [self] report in
                                finish(report?.handshakes.first.map { $0.handshakeRTT * 1_000 } ?? elapsed)
                            }
                        case .waiting(let error), .failed(let error):
                            finish(error == .posix(.ECONNREFUSED) ? elapsed : nil)
                        default:
                            break
                        }
                    }
                    connection.start(queue: queue)
                    queue.asyncAfter(deadline: .now() + timeout) { [self] in finish(nil) }
                }
            }
        }

        func cancel() {
            queue.async { [self] in finish(nil) }
        }

        private var elapsed: Double {
            Double(DispatchTime.now().uptimeNanoseconds - began.uptimeNanoseconds) / 1e6
        }

        private func finish(_ milliseconds: Double?) {
            guard !done else { return }
            done = true
            connection.stateUpdateHandler = nil
            connection.cancel()
            continuation?.resume(returning: milliseconds)
            continuation = nil
        }
    }
}
