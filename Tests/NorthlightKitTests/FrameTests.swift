import Foundation
import Testing
@testable import NorthlightKit

private let now = Date(timeIntervalSince1970: 1_800_000_000)

@Test func framesSurviveArrivingInPieces() throws {
    let frames = [Frame.agents(Samples.agents(at: now)), Frame.agents([])]
    let bytes = try frames.map { try $0.encoded() }.reduce(Data(), +)
    var reader = FrameReader()
    var read: [Frame] = []
    // Seven bytes at a time splits both the length prefixes and the bodies.
    for start in stride(from: 0, to: bytes.count, by: 7) {
        read += try reader.read(bytes[start..<min(start + 7, bytes.count)])
    }
    #expect(read == frames)
}

@Test func aFrameOverTheLimitIsRefusedBeforeItsBodyArrives() {
    var reader = FrameReader()
    // A length prefix of 2 MiB, and no body yet.
    #expect(throws: FrameReader.Oversized.self) {
        try reader.read(Data([0x00, 0x20, 0x00, 0x00]))
    }
}

@Test func pushedConnectorFramesRoundTrip() throws {
    let frames: [Frame] = [
        .events(Pushed(value: Samples.events(at: now), fetchedAt: now, interval: 600, source: "Studio Mac")),
        .github(Pushed(value: GitHubPush(summary: Samples.github(at: now), codeHistory: Samples.codeHistory(at: now)),
                       fetchedAt: now, interval: 900, source: "Studio Mac")),
        .events(Pushed(value: nil, fetchedAt: now, error: "Calendar access is off", interval: 600, source: "Studio Mac")),
        .disconnected(.calendar),
        .disconnected(.github),
    ]
    var reader = FrameReader()
    #expect(try reader.read(frames.map { try $0.encoded() }.reduce(Data(), +)) == frames)
}

@Test func aPushMissingItsOptionalFieldsStillDecodes() throws {
    // An older Mac's push carries no error and no lines of code.
    let summary = String(decoding: try JSONEncoder().encode(Samples.github(at: now)), as: UTF8.self)
    let json = #"{"github":{"_0":{"fetchedAt":0,"interval":900,"source":"Mac","value":{"summary":"# + summary + "}}}}"
    let frame = try JSONDecoder().decode(Frame.self, from: Data(json.utf8))
    guard case .github(let pushed) = frame else {
        Issue.record("not a github frame")
        return
    }
    #expect(pushed.error == nil)
    #expect(pushed.value?.codeHistory == nil)
    #expect(pushed.value?.summary == Samples.github(at: now))
}

@Test func theEditorsFramesRoundTrip() throws {
    let revision = LayoutRevision(epoch: UUID(), n: 3)
    var status = TVStatus(editing: true, page: Dashboard.starter.pages[1].id)
    status.place = Samples.place
    status.weather = Loaded(interval: 1_200, value: Samples.weather(at: now), fetchedAt: now)
    status.flights = Loaded(interval: 10, value: Samples.flights(at: now).flights, fetchedAt: now, lastError: "timed out")
    status.path = Samples.network
    status.latency = Samples.latency(at: now)
    status.speed = Samples.speedTests(at: now)
    let frames: [Frame] = [
        .hello(Hello(installID: UUID(), revision: revision, editing: false)),
        .layout(LayoutFrame(revision: revision, base: nil, dashboard: .starter)),
        .tvStatus(status),
        .showPage(Dashboard.starter.pages[0].id),
    ]
    var reader = FrameReader()
    let read = try reader.read(try frames.map { try $0.encoded() }.reduce(Data(), +))
    #expect(read == frames)
}

@Test func aFrameThisBuildCannotReadIsSkipped() throws {
    // A newer peer's kind, then one this build knows: the link carries on past it.
    let body = Data(#"{"fromTheFuture":{"_0":1}}"#.utf8)
    let unknown = Data(withUnsafeBytes(of: UInt32(body.count).bigEndian) { Array($0) }) + body
    var reader = FrameReader()
    #expect(try reader.read(unknown + Frame.agents([]).encoded()) == [.agents([])])
}

@Test func aStatusFromAnOlderTVStillReads() throws {
    let old = Data(#"{"tvStatus":{"_0":{"editing":false}}}"#.utf8)
    let status = try JSONDecoder().decode(Frame.self, from: old)
    #expect(status == .tvStatus(TVStatus(editing: false, page: nil)))
}

@Test func unreadFramesKeepOnlyTheNewestOfEachKind() async {
    let frames = Frames()
    let briefing = Frame.briefing(.written(text: "A quiet day.", at: now))
    let latest = Frame.agents(Samples.agents(at: now))
    #expect(frames.push(.agents([])))
    #expect(frames.push(briefing))
    #expect(frames.push(latest))
    frames.finish()
    var read: [Frame] = []
    for await frame in frames { read.append(frame) }
    #expect(read == [briefing, latest])
    #expect(!frames.push(.agents([])))
}
