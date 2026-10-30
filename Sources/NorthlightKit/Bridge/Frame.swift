import Foundation
import os

/// What crosses the bridge: the Mac's reports and briefings to the TV, the TV's
/// briefing requests to the Mac, and the editor's frames both ways.
public enum Frame: Codable, Sendable, Equatable {
    case agents([AgentStatus])
    case briefingRequest(BriefingRequest)
    case briefing(Briefing)
    case usage(UsageReading)
    case events(Pushed<[CalendarEvent]>)
    case github(Pushed<GitHubPush>)
    /// The Mac's user disconnected the source, so the TV forgets what it pushed.
    case disconnected(Connector)
    /// Each end's first frame. The TV answers a Mac's with its own, its layout and
    /// its status.
    case hello(Hello)
    /// From the TV, the layout it shows; from the Mac, a layout built on `base`.
    case layout(LayoutFrame)
    case tvStatus(TVStatus)
    /// Turns the TV to the page with this id.
    case showPage(UUID)

    /// The largest body the TV takes: far more than a status list, far less than a
    /// memory problem.
    public static let maxBytes = 1 << 20

    /// The body's length in four big-endian bytes, then the body as JSON.
    public func encoded() throws -> Data {
        let body = try JSONEncoder().encode(self)
        return Data(withUnsafeBytes(of: UInt32(body.count).bigEndian) { Array($0) }) + body
    }

    /// Frames of one kind replace each other while they wait to be read.
    var kind: Int {
        switch self {
        case .agents: 0
        case .briefingRequest: 1
        case .briefing: 2
        case .hello: 3
        case .layout: 4
        case .tvStatus: 5
        case .showPage: 6
        case .usage: 7
        case .events: 8
        case .github: 9
        case .disconnected(.calendar): 10
        case .disconnected(.github): 11
        }
    }
}

public struct Hello: Codable, Sendable, Equatable {
    /// 2 added the editor's frames.
    public static let currentProtocol = 2

    public var protocolVersion: Int
    public var schema: Int
    public var installID: UUID
    /// The TV's layout revision; nil from a Mac.
    public var revision: LayoutRevision?
    public var editing: Bool

    public init(protocolVersion: Int = Hello.currentProtocol, schema: Int = Dashboard.schema, installID: UUID,
                revision: LayoutRevision?, editing: Bool) {
        self.protocolVersion = protocolVersion
        self.schema = schema
        self.installID = installID
        self.revision = revision
        self.editing = editing
    }
}

public struct LayoutFrame: Codable, Sendable, Equatable {
    /// The TV's revision after this layout. A Mac sends the revision it edited.
    public var revision: LayoutRevision
    /// The revision the Mac's edit was built on: on the TV's echo, the Mac edit it
    /// applied, if any.
    public var base: LayoutRevision?
    public var dashboard: Dashboard

    public init(revision: LayoutRevision, base: LayoutRevision?, dashboard: Dashboard) {
        self.revision = revision
        self.base = base
        self.dashboard = dashboard
    }
}

/// What the TV is doing and showing, so the Mac's mirror draws the TV's own readings.
/// A field left out keeps the Mac's last copy of it, so the TV sends flights and the
/// network history only now and then.
public struct TVStatus: Codable, Sendable, Equatable {
    public var editing: Bool
    public var page: UUID?
    public var place: Place?
    public var units: Units?
    public var flightRadiusNM: Int?
    public var path: NetworkPath?
    public var latency: LatencyHistory?
    public var speed: [SpeedResult]?
    public var weather: Loaded<Weather>?
    public var alerts: Loaded<[WeatherAlert]>?
    public var aurora: Loaded<Aurora>?
    public var quakes: Loaded<[Quake]>?
    public var airQuality: Loaded<AirQuality>?
    public var flights: Loaded<[Flight]>?
    public var spaceWeather: Loaded<SpaceWeather>?
    public var xrays: Loaded<[SpaceWeather.XRay]>?
    public var iss: Loaded<ISSTrack>?
    public var launches: Loaded<[Launch]>?
    public var hackerNews: Loaded<[HNStory]>?
    public var serviceStatus: Loaded<[ServiceStatus]>?
    public var crypto: Loaded<CryptoMarket>?
    public var rates: Loaded<ExchangeRates>?

    public init(editing: Bool, page: UUID?) {
        self.editing = editing
        self.page = page
    }

    /// This status with the fields it leaves out taken from `older`.
    public func filled(from older: TVStatus) -> TVStatus {
        var merged = self
        merged.place = place ?? older.place
        merged.units = units ?? older.units
        merged.flightRadiusNM = flightRadiusNM ?? older.flightRadiusNM
        merged.path = path ?? older.path
        merged.latency = latency ?? older.latency
        merged.speed = speed ?? older.speed
        merged.weather = weather ?? older.weather
        merged.alerts = alerts ?? older.alerts
        merged.aurora = aurora ?? older.aurora
        merged.quakes = quakes ?? older.quakes
        merged.airQuality = airQuality ?? older.airQuality
        merged.flights = flights ?? older.flights
        merged.spaceWeather = spaceWeather ?? older.spaceWeather
        merged.xrays = xrays ?? older.xrays
        merged.iss = iss ?? older.iss
        merged.launches = launches ?? older.launches
        merged.hackerNews = hackerNews ?? older.hackerNews
        merged.serviceStatus = serviceStatus ?? older.serviceStatus
        merged.crypto = crypto ?? older.crypto
        merged.rates = rates ?? older.rates
        return merged
    }
}

/// Collects bytes as they arrive and hands back each frame once all of it is in. A
/// frame this build cannot read, such as a kind from a newer peer, is skipped, since
/// its length says where the next one starts.
public struct FrameReader: Sendable {
    public struct Oversized: Error {
        public let bytes: Int
    }

    private var buffer = Data()

    public init() {}

    public mutating func read(_ bytes: Data) throws -> [Frame] {
        buffer.append(bytes)
        var frames: [Frame] = []
        while buffer.count >= 4 {
            let length = buffer.prefix(4).reduce(0) { $0 << 8 | Int($1) }
            guard length <= Frame.maxBytes else { throw Oversized(bytes: length) }
            guard buffer.count >= 4 + length else { break }
            if let frame = try? JSONDecoder().decode(Frame.self, from: buffer.dropFirst(4).prefix(length)) {
                frames.append(frame)
            }
            buffer = Data(buffer.dropFirst(4 + length))
        }
        return frames
    }
}

/// Frames waiting to be read, at most one of each kind: a newer frame replaces an
/// unread one of its kind, so a burst of reports never pushes out a briefing and a
/// reader behind on requests answers the latest. Read by one task at a time.
public final class Frames: AsyncSequence, Sendable {
    private struct State {
        var pending: [Frame] = []
        var finished = false
        var waiter: CheckedContinuation<Frame?, Never>?
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let onFinish: @Sendable () -> Void

    init(onFinish: @escaping @Sendable () -> Void = {}) {
        self.onFinish = onFinish
    }

    /// False once finished, when the frame is dropped.
    @discardableResult
    func push(_ frame: Frame) -> Bool {
        let (taken, waiter) = state.withLock { state -> (Bool, CheckedContinuation<Frame?, Never>?) in
            guard !state.finished else { return (false, nil) }
            if let waiter = state.waiter {
                state.waiter = nil
                return (true, waiter)
            }
            state.pending.removeAll { $0.kind == frame.kind }
            state.pending.append(frame)
            return (true, nil)
        }
        waiter?.resume(returning: frame)
        return taken
    }

    /// Ends the sequence once the frames waiting are read.
    func finish() {
        let (first, waiter) = state.withLock { state -> (Bool, CheckedContinuation<Frame?, Never>?) in
            defer { state.finished = true; state.waiter = nil }
            return (!state.finished, state.waiter)
        }
        waiter?.resume(returning: nil)
        if first { onFinish() }
    }

    private func next() async -> Frame? {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let ready = state.withLock { state -> Frame?? in
                    if !state.pending.isEmpty { return .some(state.pending.removeFirst()) }
                    if state.finished || Task.isCancelled { return .some(nil) }
                    state.waiter = continuation
                    return .none
                }
                if let ready { continuation.resume(returning: ready) }
            }
        } onCancel: {
            state.withLock { state in
                defer { state.waiter = nil }
                return state.waiter
            }?.resume(returning: nil)
        }
    }

    public struct AsyncIterator: AsyncIteratorProtocol, Sendable {
        let frames: Frames
        public func next() async -> Frame? { await frames.next() }
    }

    public func makeAsyncIterator() -> AsyncIterator { AsyncIterator(frames: self) }
}
