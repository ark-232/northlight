import Foundation

/// M-Lab's ndt7 speed test: the server Locate v2 names, and the arithmetic over what a
/// test sends back. Speeds are megabits a second; latencies, milliseconds.
public enum NDT7 {
    public struct Server: Equatable, Sendable {
        /// Where the server is, such as "Seattle, US".
        public let name: String
        public let download: URL
        public let upload: URL
    }

    private struct Locate: Decodable {
        struct Result: Decodable {
            struct Location: Decodable {
                var city: String?
                var country: String?
            }
            var machine: String
            var location: Location?
            var urls: [String: String]
        }
        var results: [Result]?
    }

    /// The nearest server's addresses over TLS. The download stops early at 250 MB, the
    /// one cap the server accepts.
    public static func server(fromLocate data: Data) throws -> Server {
        guard let result = try decodeFeed(Locate.self, from: data).results?.first,
              let download = result.urls["wss:///ndt/v7/download"].flatMap({ URLComponents(string: $0) }),
              let upload = result.urls["wss:///ndt/v7/upload"].flatMap({ URL(string: $0) })
        else { throw FeedError.decode("Locate named no ndt7 server") }
        var capped = download
        capped.percentEncodedQuery = (download.percentEncodedQuery.map { $0 + "&" } ?? "") + "early_exit=250"
        let place = [result.location?.city, result.location?.country].compactMap { $0 }.joined(separator: ", ")
        return Server(name: place.isEmpty ? result.machine : place, download: capped.url!, upload: upload)
    }

    /// A measurement the server sends during a test. Times are microseconds.
    public struct Measurement: Decodable, Equatable, Sendable {
        public struct TCPInfo: Decodable, Equatable, Sendable {
            public var elapsedTime: Int64
            public var minRTT: Int64?
            public var rtt: Int64?
            public var bytesReceived: Int64?

            enum CodingKeys: String, CodingKey {
                case elapsedTime = "ElapsedTime", minRTT = "MinRTT", rtt = "RTT", bytesReceived = "BytesReceived"
            }
        }

        public var tcpInfo: TCPInfo?

        enum CodingKeys: String, CodingKey {
            case tcpInfo = "TCPInfo"
        }
    }

    public static func measurement(from text: String) throws -> Measurement {
        try decodeFeed(Measurement.self, from: Data(text.utf8))
    }

    public static func megabits(bytes: Int64, seconds: Double) -> Double {
        Double(bytes) * 8 / seconds / 1_000_000
    }

    /// What the server says it received, over its own clock.
    public static func uploadMegabits(from measurements: [Measurement]) -> Double? {
        guard let last = measurements.compactMap(\.tcpInfo).last(where: { $0.bytesReceived != nil && $0.elapsedTime > 0 }),
              let bytes = last.bytesReceived
        else { return nil }
        return megabits(bytes: bytes, seconds: Double(last.elapsedTime) / 1_000_000)
    }

    /// The least round trip the connection saw.
    public static func idleLatency(from measurements: [Measurement]) -> Double? {
        measurements.compactMap(\.tcpInfo?.minRTT).min().map { Double($0) / 1_000 }
    }

    /// The round trip under load: the mean of the samples after the first three seconds,
    /// with the slowest 5 % trimmed. A fast link reaches the 250 MB cap sooner, and then
    /// every sample counts.
    public static func loadedLatency(from measurements: [Measurement]) -> Double? {
        let samples = measurements.compactMap(\.tcpInfo)
        let settled = samples.filter { $0.elapsedTime >= 3_000_000 }
        let loaded = (settled.isEmpty ? samples : settled).compactMap(\.rtt).sorted()
        guard !loaded.isEmpty else { return nil }
        let kept = loaded.prefix(max(1, loaded.count * 95 / 100))
        return Double(kept.reduce(0, +)) / Double(kept.count) / 1_000
    }

    /// An upload message doubles while it is under a sixteenth of the bytes sent, up to
    /// 1 MiB, as the protocol suggests.
    public static func nextMessageSize(after size: Int, sent: Int64) -> Int {
        Int64(size) < sent / 16 ? min(size * 2, 1 << 20) : size
    }
}

/// A test's speed so far, for the live curve.
public struct ThroughputPoint: Equatable, Sendable {
    public enum Direction: Sendable { case download, upload }

    public var direction: Direction
    /// Seconds into this direction's run.
    public var seconds: Double
    public var megabits: Double

    public init(direction: Direction, seconds: Double, megabits: Double) {
        self.direction = direction
        self.seconds = seconds
        self.megabits = megabits
    }
}

/// One speed test's outcome.
public struct SpeedResult: Codable, Equatable, Sendable {
    public enum Responsiveness: String, Codable, Sendable {
        case poor, fair, good, excellent
    }

    public var date: Date
    /// Where the server was, such as "Seattle, US".
    public var server: String
    public var downloadMegabits: Double
    public var uploadMegabits: Double
    /// The least round trip, in milliseconds.
    public var idleLatency: Double
    /// The round trip while downloading, in milliseconds.
    public var loadedLatency: Double

    /// Round trips a minute under load.
    public var rpm: Double { 60_000 / loadedLatency }

    /// The tiers of draft-ietf-ippm-responsiveness-09: 300 RPM or worse is poor, 6000 or
    /// better excellent.
    public var responsiveness: Responsiveness {
        switch rpm {
        case ...300: .poor
        case ..<1_000: .fair
        case ..<6_000: .good
        default: .excellent
        }
    }
}

extension HTTP {
    /// The nearest M-Lab server, from Locate v2.
    public func nearestNDT7Server(clientVersion: String) async throws -> NDT7.Server {
        let url = makeURL("https://locate.measurementlab.net/v2/nearest/ndt/ndt7",
                          ["client_name": "northlight", "client_version": clientVersion])
        return try NDT7.server(fromLocate: try await data(url, accept: "application/json"))
    }

    /// One ndt7 test on `server`: the download, then the upload, each for as long as the
    /// server runs it, ten seconds on M-Lab's. `progress` hears each direction's speed so
    /// far, about four times a second, its last point the result's.
    public func speedTest(on server: NDT7.Server, seconds: Double = 10,
                          progress: @escaping @Sendable (ThroughputPoint) -> Void = { _ in }) async throws -> SpeedResult {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.allowsExpensiveNetworkAccess = false
        configuration.allowsConstrainedNetworkAccess = false
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 10
        configuration.httpAdditionalHeaders = ["User-Agent": userAgent]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        let download = try await receive(from: server.download, in: session, for: seconds, progress: progress)
        let upload = try await send(to: server.upload, in: session, for: seconds, progress: progress)
        guard let uploadMegabits = NDT7.uploadMegabits(from: upload),
              let idle = NDT7.idleLatency(from: download.measurements),
              let loaded = NDT7.loadedLatency(from: download.measurements)
        else { throw FeedError.refused("The server reported too little to measure.") }
        return SpeedResult(date: Date(), server: server.name,
                           downloadMegabits: NDT7.megabits(bytes: download.bytes, seconds: download.seconds),
                           uploadMegabits: uploadMegabits, idleLatency: idle, loadedLatency: loaded)
    }

    /// Counts what the server sends until it closes, or three seconds past its time.
    private func receive(from url: URL, in session: URLSession, for seconds: Double,
                         progress: @Sendable (ThroughputPoint) -> Void) async throws
        -> (bytes: Int64, seconds: Double, measurements: [NDT7.Measurement]) {
        let task = session.webSocketTask(with: url, protocols: ["net.measurementlab.ndt.v7"])
        task.maximumMessageSize = 1 << 24
        task.resume()
        let watchdog = Task {
            try await Task.sleep(for: .seconds(seconds + 3))
            task.cancel(with: .goingAway, reason: nil)
        }
        defer {
            watchdog.cancel()
            task.cancel(with: .normalClosure, reason: nil)
        }
        var bytes: Int64 = 0
        var measurements: [NDT7.Measurement] = []
        var first: ContinuousClock.Instant?, last = ContinuousClock.now
        var published = 0.0
        while let message = try? await task.receive() {
            last = .now
            first = first ?? last
            switch message {
            case .data(let data): bytes += Int64(data.count)
            case .string(let text): if let measurement = try? NDT7.measurement(from: text) { measurements.append(measurement) }
            @unknown default: break
            }
            let elapsed = first.map { $0.duration(to: last) / .seconds(1) } ?? 0
            if elapsed - published >= 0.25 {
                published = elapsed
                progress(ThroughputPoint(direction: .download, seconds: elapsed, megabits: NDT7.megabits(bytes: bytes, seconds: elapsed)))
            }
        }
        let elapsed = first.map { $0.duration(to: last) / .seconds(1) } ?? 0
        try ended(task, after: elapsed, of: seconds)
        if elapsed > 0 {
            progress(ThroughputPoint(direction: .download, seconds: elapsed, megabits: NDT7.megabits(bytes: bytes, seconds: elapsed)))
        }
        return (bytes, elapsed, measurements)
    }

    /// Sends noise for `seconds` while the server reports what it received.
    private func send(to url: URL, in session: URLSession, for seconds: Double,
                      progress: @escaping @Sendable (ThroughputPoint) -> Void) async throws -> [NDT7.Measurement] {
        let task = session.webSocketTask(with: url, protocols: ["net.measurementlab.ndt.v7"])
        task.resume()
        // The server closes at its time; a send that never returns, or a close that never
        // comes, ends three seconds past ours.
        let watchdog = Task {
            try await Task.sleep(for: .seconds(seconds + 3))
            task.cancel(with: .goingAway, reason: nil)
        }
        defer {
            watchdog.cancel()
            task.cancel(with: .normalClosure, reason: nil)
        }
        let reports = Task {
            var measurements: [NDT7.Measurement] = []
            while let message = try? await task.receive() {
                if case .string(let text) = message, let measurement = try? NDT7.measurement(from: text) {
                    measurements.append(measurement)
                    if let info = measurement.tcpInfo, let received = info.bytesReceived, info.elapsedTime > 0 {
                        let elapsed = Double(info.elapsedTime) / 1_000_000
                        progress(ThroughputPoint(direction: .upload, seconds: elapsed,
                                                 megabits: NDT7.megabits(bytes: received, seconds: elapsed)))
                    }
                }
            }
            return measurements
        }
        let start = ContinuousClock.now
        var size = 1 << 13, sent: Int64 = 0
        var noise = Data((0..<size).map { _ in UInt8.random(in: .min ... .max) })
        while start.duration(to: .now) < .seconds(seconds), (try? await task.send(.data(noise))) != nil {
            sent += Int64(size)
            let next = NDT7.nextMessageSize(after: size, sent: sent)
            if next != size {
                size = next
                noise = Data((0..<size).map { _ in UInt8.random(in: .min ... .max) })
            }
        }
        let measurements = await reports.value
        try ended(task, after: start.duration(to: .now) / .seconds(1), of: seconds)
        return measurements
    }

    /// A test the server did not close, and that stopped before its time, failed.
    private func ended(_ task: URLSessionWebSocketTask, after elapsed: Double, of seconds: Double) throws {
        guard task.closeCode == .normalClosure || elapsed >= seconds else {
            throw FeedError.refused("The test stopped after \(Int(elapsed)) s: \(task.error?.localizedDescription ?? "no reason given")")
        }
    }
}

/// When automatic speed tests run: gaps drawn as in a Poisson process with a twelve-hour
/// mean, so tests never settle on a clock time, each held between two and twenty-four
/// hours, and never a fifth test in a day, M-Lab's limit for automated clients.
public enum SpeedSchedule {
    /// `uniform` is a draw from [0, 1).
    public static func next(from now: Date, history: [Date], uniform: Double) -> Date {
        let gap = min(max(-log(1 - uniform) * 12 * 3_600, 2 * 3_600), 24 * 3_600)
        let next = now.addingTimeInterval(gap)
        let lastFour = history.sorted().suffix(4)
        guard lastFour.count == 4, let oldest = lastFour.first else { return next }
        return max(next, oldest.addingTimeInterval(24 * 3_600))
    }

    /// The tests in the day the limit counts: the last 24 hours, manual ones included.
    public static func count(in history: [Date], asOf now: Date) -> Int {
        history.filter { now.timeIntervalSince($0) < 24 * 3_600 }.count
    }
}
