import Foundation
import Network
import Testing
@testable import NorthlightKit

/// A local stand-in for an ndt7 server, one listener per direction. A download sends
/// 64 KiB messages and a measurement every 100 ms; an upload counts what arrives and
/// reports it, as ndt-server does. Each closes after `seconds`, and reports its clock
/// ten times fast, so a one-second run reads as the ten seconds a real test takes.
private final class FakeNDT7: @unchecked Sendable {
    enum Direction: String { case download, upload }

    private let direction: Direction
    private let seconds: Double
    private let listener: NWListener
    private let queue = DispatchQueue(label: "fake-ndt7")
    private var began = DispatchTime.now()
    private var lastReport = DispatchTime.now()
    private var received: Int64 = 0

    init(_ direction: Direction, seconds: Double) throws {
        self.direction = direction
        self.seconds = seconds
        let webSocket = NWProtocolWebSocket.Options()
        webSocket.setClientRequestHandler(queue) { subprotocols, _ in
            NWProtocolWebSocket.Response(status: .accept, subprotocol: subprotocols.first)
        }
        let parameters = NWParameters.tcp
        parameters.defaultProtocolStack.applicationProtocols.insert(webSocket, at: 0)
        listener = try NWListener(using: parameters, on: .any)
    }

    func start() async throws -> URL {
        listener.newConnectionHandler = { [self] connection in
            connection.stateUpdateHandler = { [self] state in
                guard case .ready = state else { return }
                began = .now()
                lastReport = began
                switch direction {
                case .download: sendDownload(connection)
                case .upload: receiveUpload(connection)
                }
            }
            connection.start(queue: queue)
        }
        let port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<NWEndpoint.Port, any Error>) in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready: continuation.resume(returning: listener.port!)
                case .failed(let error): continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: queue)
        }
        return URL(string: "ws://127.0.0.1:\(port.rawValue)/ndt/v7/\(direction.rawValue)")!
    }

    func cancel() {
        listener.cancel()
    }

    private var elapsed: Double { Double(DispatchTime.now().uptimeNanoseconds - began.uptimeNanoseconds) / 1e9 }

    /// A measurement every 100 ms, with the clock read ten times fast.
    private func reportIfDue(on connection: NWConnection) {
        guard Double(DispatchTime.now().uptimeNanoseconds - lastReport.uptimeNanoseconds) / 1e9 >= 0.1 else { return }
        lastReport = .now()
        let report = #"{"TCPInfo":{"ElapsedTime":\#(Int64(elapsed * 10_000_000)),"MinRTT":5000,"RTT":8000,"BytesReceived":\#(received)}}"#
        send(Data(report.utf8), .text, on: connection)
    }

    private func sendDownload(_ connection: NWConnection) {
        guard elapsed < seconds else { return close(connection) }
        reportIfDue(on: connection)
        send(Data(count: 65_536), .binary, on: connection) { [self] in sendDownload(connection) }
    }

    private func receiveUpload(_ connection: NWConnection) {
        connection.receiveMessage { [self] content, _, _, error in
            guard error == nil else { return }
            received += Int64(content?.count ?? 0)
            reportIfDue(on: connection)
            if elapsed < seconds { receiveUpload(connection) } else { close(connection) }
        }
    }

    private func send(_ data: Data?, _ opcode: NWProtocolWebSocket.Opcode, on connection: NWConnection,
                      then next: (@Sendable () -> Void)? = nil) {
        let metadata = NWProtocolWebSocket.Metadata(opcode: opcode)
        if opcode == .close { metadata.closeCode = .protocolCode(.normalClosure) }
        let context = NWConnection.ContentContext(identifier: "\(opcode)", metadata: [metadata])
        connection.send(content: data, contentContext: context, isComplete: true, completion: .contentProcessed { error in
            if error == nil { next?() }
        })
    }

    private func close(_ connection: NWConnection) {
        send(nil, .close, on: connection)
    }
}

@Test(.timeLimit(.minutes(1)))
func aSpeedTestRunsBothDirectionsAgainstAnNDT7Server() async throws {
    let download = try FakeNDT7(.download, seconds: 1), upload = try FakeNDT7(.upload, seconds: 1)
    defer { download.cancel(); upload.cancel() }
    let server = NDT7.Server(name: "Loopback", download: try await download.start(), upload: try await upload.start())

    let result = try await HTTP(userAgent: "Northlight/test").speedTest(on: server, seconds: 1)
    #expect(result.server == "Loopback")
    #expect(result.downloadMegabits > 0)
    #expect(result.uploadMegabits > 0)
    #expect(result.idleLatency == 5)
    #expect(result.loadedLatency == 8)
}

private final class Collected: @unchecked Sendable {
    private let lock = NSLock()
    private var points: [ThroughputPoint] = []

    func append(_ point: ThroughputPoint) { lock.withLock { points.append(point) } }
    var all: [ThroughputPoint] { lock.withLock { points } }
}

/// Download points come from the bytes the TV counted, upload points from what the server
/// says it received, and each direction's curve ends on the result.
@Test(.timeLimit(.minutes(1)))
func aSpeedTestPublishesItsThroughputAsItRunsAndEndsOnTheResult() async throws {
    let download = try FakeNDT7(.download, seconds: 1), upload = try FakeNDT7(.upload, seconds: 1)
    defer { download.cancel(); upload.cancel() }
    let server = NDT7.Server(name: "Loopback", download: try await download.start(), upload: try await upload.start())
    let collected = Collected()

    let result = try await HTTP(userAgent: "Northlight/test").speedTest(on: server, seconds: 1, progress: collected.append)
    let points = collected.all
    let downloads = points.filter { $0.direction == .download }, uploads = points.filter { $0.direction == .upload }
    #expect(downloads.count > 1)
    #expect(uploads.count > 1)
    #expect(points.firstIndex { $0.direction == .upload }! > points.lastIndex { $0.direction == .download }!)
    for curve in [downloads, uploads] {
        #expect(zip(curve, curve.dropFirst()).allSatisfy { $0.seconds <= $1.seconds })
    }
    #expect(downloads.last?.megabits == result.downloadMegabits)
    #expect(uploads.last?.megabits == result.uploadMegabits)
}
