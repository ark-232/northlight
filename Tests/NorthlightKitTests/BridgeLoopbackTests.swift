import CryptoKit
import Foundation
import Network
import Testing
@testable import NorthlightKit

private func listen(_ key: SymmetricKey) async throws -> (BridgeListener, NWEndpoint) {
    let listener = try BridgeListener(key: key)
    let port = try await listener.start()
    return (listener, .hostPort(host: "127.0.0.1", port: port))
}

@Test(.timeLimit(.minutes(1)))
func aFrameCrossesTheBridge() async throws {
    let key = SymmetricKey(size: .bits256)
    let (tv, address) = try await listen(key)
    defer { tv.cancel() }
    let mac = BridgeConnection(to: address, key: key)
    defer { mac.cancel() }

    try await mac.ready()
    let frame = Frame.agents(Samples.agents(at: Date(timeIntervalSince1970: 1_800_000_000)))
    try await mac.send(frame)
    var frames = tv.frames.makeAsyncIterator()
    #expect(await frames.next() == frame)
}

@Test(.timeLimit(.minutes(1)))
func aMacWithTheWrongKeyIsRefused() async throws {
    let key = SymmetricKey(size: .bits256)
    let (tv, address) = try await listen(key)
    defer { tv.cancel() }
    let stranger = BridgeConnection(to: address, key: SymmetricKey(size: .bits256))
    defer { stranger.cancel() }
    await #expect(throws: (any Error).self) { try await stranger.ready() }

    // The TV still takes its own Mac afterwards.
    let mac = BridgeConnection(to: address, key: key)
    defer { mac.cancel() }
    try await mac.ready()
}

@Test(.timeLimit(.minutes(1)))
func aStoppedListenerClosesItsMacsConnections() async throws {
    let key = SymmetricKey(size: .bits256)
    let (tv, address) = try await listen(key)
    let mac = BridgeConnection(to: address, key: key)
    defer { mac.cancel() }
    try await mac.ready()
    try await mac.send(.agents([]))

    // The Mac learns the TV went away from its next sends, and connects again.
    tv.cancel()
    var refused = false
    for _ in 0..<50 where !refused {
        try await Task.sleep(for: .milliseconds(100))
        refused = (try? await mac.send(.agents([]))) == nil
    }
    #expect(refused)
}

@Test(.timeLimit(.minutes(1)))
func aTVThatNeverAnswersTimesOut() async throws {
    // A plain TCP listener accepts the connection and never speaks TLS.
    let silent = try NWListener(using: .tcp)
    silent.newConnectionHandler = { $0.start(queue: .main) }
    let port: NWEndpoint.Port = try await withCheckedThrowingContinuation { ready in
        silent.stateUpdateHandler = { state in
            if case .ready = state {
                silent.stateUpdateHandler = nil
                ready.resume(returning: silent.port!)
            }
        }
        silent.start(queue: .main)
    }
    defer { silent.cancel() }

    let mac = BridgeConnection(to: .hostPort(host: "127.0.0.1", port: port), key: SymmetricKey(size: .bits256))
    defer { mac.cancel() }
    let started = Date()
    await #expect(throws: (any Error).self) { try await mac.ready(within: .seconds(1)) }
    #expect(Date().timeIntervalSince(started) < 10)
}

@Test(.timeLimit(.minutes(1)))
func theTVAsksItsMacAndHearsBack() async throws {
    let key = SymmetricKey(size: .bits256)
    let (tv, address) = try await listen(key)
    defer { tv.cancel() }
    let mac = BridgeConnection(to: address, key: key)
    defer { mac.cancel() }
    try await mac.ready()

    // The TV learns its Mac from the Mac's first report.
    try await mac.send(.agents([]))
    var fromMac = tv.frames.makeAsyncIterator()
    #expect(await fromMac.next() == .agents([]))

    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let request = Frame.briefingRequest(BriefingRequest(place: Samples.place, at: now, locale: "en_US", units: nil,
                                                        weather: nil, events: [], alerts: []))
    try tv.send(request)
    var fromTV = mac.frames.makeAsyncIterator()
    #expect(await fromTV.next() == request)

    let reply = Frame.briefing(.written(text: "A quiet day.", at: now))
    try await mac.send(reply)
    #expect(await fromMac.next() == reply)
}

@Test(.timeLimit(.minutes(1)))
func aMacThatGoesIsForgotten() async throws {
    let key = SymmetricKey(size: .bits256)
    let (tv, address) = try await listen(key)
    defer { tv.cancel() }
    let mac = BridgeConnection(to: address, key: key)
    try await mac.ready()
    try await mac.send(.agents([]))
    var fromMac = tv.frames.makeAsyncIterator()
    _ = await fromMac.next()
    #expect(tv.connectedMacs == 1)

    mac.cancel()
    for _ in 0..<50 where tv.connectedMacs > 0 {
        try await Task.sleep(for: .milliseconds(100))
    }
    #expect(tv.connectedMacs == 0)
}

@Test(.timeLimit(.minutes(1)))
func aMacBehindOnRequestsAnswersOnlyTheNewest() async throws {
    let key = SymmetricKey(size: .bits256)
    let (tv, address) = try await listen(key)
    defer { tv.cancel() }
    let mac = BridgeConnection(to: address, key: key)
    defer { mac.cancel() }
    try await mac.ready()
    try await mac.send(.agents([]))
    var fromMac = tv.frames.makeAsyncIterator()
    _ = await fromMac.next()

    let requests = (0..<3).map {
        Frame.briefingRequest(BriefingRequest(place: Samples.place, at: Date(timeIntervalSince1970: 1_800_000_000 + Double($0)),
                                              locale: "en_US", units: nil, weather: nil, events: [], alerts: []))
    }
    for request in requests { try tv.send(request) }
    try await Task.sleep(for: .milliseconds(500))
    var fromTV = mac.frames.makeAsyncIterator()
    #expect(await fromTV.next() == requests.last)
}

@Test(.timeLimit(.minutes(1)))
func theMacsFramesEndWhenTheTVGoes() async throws {
    let key = SymmetricKey(size: .bits256)
    let (tv, address) = try await listen(key)
    let mac = BridgeConnection(to: address, key: key)
    defer { mac.cancel() }
    try await mac.ready()
    try await mac.send(.agents([]))
    var fromMac = tv.frames.makeAsyncIterator()
    _ = await fromMac.next()

    tv.cancel()
    var fromTV = mac.frames.makeAsyncIterator()
    #expect(await fromTV.next() == nil)
}

@Test(.timeLimit(.minutes(1)))
func aBriefingIsNotLostBehindABurstOfReports() async throws {
    let key = SymmetricKey(size: .bits256)
    let (tv, address) = try await listen(key)
    defer { tv.cancel() }
    let mac = BridgeConnection(to: address, key: key)
    defer { mac.cancel() }
    try await mac.ready()

    let briefing = Frame.briefing(.written(text: "A quiet day.", at: Date(timeIntervalSince1970: 1_800_000_000)))
    for _ in 0..<20 { try await mac.send(.agents([])) }
    try await mac.send(briefing)
    try await Task.sleep(for: .milliseconds(500))
    var fromMac = tv.frames.makeAsyncIterator()
    var read: [Frame] = []
    while read.last != briefing, let frame = await fromMac.next() { read.append(frame) }
    #expect(read.count <= 8)
    #expect(read.last == briefing)
}

@Test(.timeLimit(.minutes(1)))
func theLayoutEchoSurvivesABurstOfStatus() async throws {
    let key = SymmetricKey(size: .bits256)
    let (tv, address) = try await listen(key)
    defer { tv.cancel() }
    let mac = BridgeConnection(to: address, key: key)
    defer { mac.cancel() }
    try await mac.ready()
    try await mac.send(.hello(Hello(installID: UUID(), revision: nil, editing: false)))
    var fromMac = tv.frames.makeAsyncIterator()
    _ = await fromMac.next()

    let layout = Frame.layout(LayoutFrame(revision: LayoutRevision(epoch: UUID(), n: 1), base: nil, dashboard: .starter))
    for _ in 0..<20 { try tv.send(.tvStatus(TVStatus(editing: false, page: nil))) }
    try tv.send(layout)
    try await Task.sleep(for: .milliseconds(500))
    var fromTV = mac.frames.makeAsyncIterator()
    var read: [Frame] = []
    while read.last != layout, let frame = await fromTV.next() { read.append(frame) }
    #expect(read.count <= 2)
    #expect(read.last == layout)
}

@Test(.timeLimit(.minutes(1)))
func aLayoutGoesToTheTVAndBackWithinASecond() async throws {
    let key = SymmetricKey(size: .bits256)
    let (tv, address) = try await listen(key)
    defer { tv.cancel() }
    let mac = BridgeConnection(to: address, key: key)
    defer { mac.cancel() }
    try await mac.ready()

    let base = LayoutRevision(epoch: UUID(), n: 4)
    let echo = Task {
        for await case .layout(let proposed) in tv.frames {
            try tv.send(.layout(LayoutFrame(revision: proposed.base!.next, base: proposed.base, dashboard: proposed.dashboard)))
            return
        }
    }
    let started = ContinuousClock.now
    try await mac.send(.layout(LayoutFrame(revision: base, base: base, dashboard: .starter)))
    var fromTV = mac.frames.makeAsyncIterator()
    let answer = await fromTV.next()
    let elapsed = ContinuousClock.now - started
    try await echo.value
    #expect(answer == .layout(LayoutFrame(revision: base.next, base: base, dashboard: .starter)))
    #expect(elapsed < .seconds(1))
}
