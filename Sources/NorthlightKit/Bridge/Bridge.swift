import CryptoKit
import Foundation
import Network
import os

/// The link from the Mac to the TV on the local network: TLS 1.2 with a key both
/// already hold, so there is no certificate to issue and nothing to type.
public enum Bridge {
    public static let serviceType = "_northlight._tcp"

    static func parameters(key: SymmetricKey) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let secret = key.withUnsafeBytes { DispatchData(bytes: $0) }
        let identity = Data("northlight".utf8).withUnsafeBytes { DispatchData(bytes: $0) }
        sec_protocol_options_add_pre_shared_key(tls.securityProtocolOptions, secret as __DispatchData, identity as __DispatchData)
        // The key agreement keeps recorded traffic sealed even if the key leaks later.
        sec_protocol_options_append_tls_ciphersuite(tls.securityProtocolOptions,
                                                    tls_ciphersuite_t(rawValue: UInt16(TLS_ECDHE_PSK_WITH_CHACHA20_POLY1305_SHA256))!)
        sec_protocol_options_set_max_tls_protocol_version(tls.securityProtocolOptions, .TLSv12)
        return NWParameters(tls: tls, tcp: NWProtocolTCP.Options())
    }
}

/// The TV's end: it listens, hands over every frame a Mac holding the key sends, and
/// sends to the Macs connected to it. Only the newest unread frame of each kind waits,
/// since each report replaces the last, but a briefing must not be lost behind one.
public final class BridgeListener: Sendable {
    public let frames: Frames
    private let listener: NWListener
    private let accepted: OSAllocatedUnfairLock<[NWConnection]>
    private let queue = DispatchQueue(label: "Northlight.BridgeListener")

    /// Advertises `service` over Bonjour when one is given.
    public init(key: SymmetricKey, service: NWListener.Service? = nil) throws {
        let listener = try NWListener(using: Bridge.parameters(key: key))
        listener.service = service
        let accepted = OSAllocatedUnfairLock<[NWConnection]>(initialState: [])
        // Ending the frames closes every Mac's connection, so each Mac sees the TV
        // go and connects again to whichever listener comes next.
        let frames = Frames {
            listener.cancel()
            accepted.withLock { $0.forEach { $0.cancel() } }
        }
        self.listener = listener
        self.accepted = accepted
        self.frames = frames
        listener.newConnectionHandler = { [queue] connection in
            accepted.withLock { $0.append(connection) }
            let id = ObjectIdentifier(connection)
            connection.stateUpdateHandler = { state in
                switch state {
                case .cancelled, .failed: accepted.withLock { $0.removeAll { ObjectIdentifier($0) == id } }
                default: break
                }
            }
            connection.start(queue: queue)
            Self.receive(from: connection, reader: FrameReader(), into: frames)
        }
    }

    /// Starts listening and returns the port the system gave it. A failure after
    /// that ends `frames`.
    public func start() async throws -> NWEndpoint.Port {
        try await withCheckedThrowingContinuation { started in
            listener.stateUpdateHandler = { [listener, frames] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = { state in
                        switch state {
                        case .waiting, .failed: frames.finish()
                        default: break
                        }
                    }
                    started.resume(returning: listener.port!)
                case .waiting(let error), .failed(let error):
                    listener.stateUpdateHandler = nil
                    started.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    public func cancel() {
        frames.finish()
    }

    var connectedMacs: Int { accepted.withLock(\.count) }

    /// Sends to every Mac connected now. A Mac that has gone misses it.
    public func send(_ frame: Frame) throws {
        let data = try frame.encoded()
        for connection in accepted.withLock({ $0 }) where connection.state == .ready {
            connection.send(content: data, completion: .contentProcessed { _ in })
        }
    }

    /// Reads frames until the peer goes away or announces one over the size limit.
    static func receive(from connection: NWConnection, reader: FrameReader, into frames: Frames) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { data, _, isComplete, error in
            var reader = reader
            guard let read = try? reader.read(data ?? Data()) else {
                connection.cancel()
                return
            }
            for frame in read {
                if !frames.push(frame) {
                    connection.cancel()
                    return
                }
            }
            guard !isComplete, error == nil else {
                connection.cancel()
                return
            }
            receive(from: connection, reader: reader, into: frames)
        }
    }
}

/// The Mac's end: one connection to a TV, and what the TV sends over it.
public final class BridgeConnection: Sendable {
    /// Ends when the TV goes, which also makes the next send fail.
    public let frames = Frames()
    private let connection: NWConnection
    private let queue = DispatchQueue(label: "Northlight.BridgeConnection")

    public init(to endpoint: NWEndpoint, key: SymmetricKey) {
        connection = NWConnection(to: endpoint, using: Bridge.parameters(key: key))
    }

    /// Connects, or throws when the TV cannot be reached, refuses the key, or has not
    /// finished the handshake within `timeout`. A refused key leaves the connection
    /// waiting rather than failed, so waiting counts as a failure.
    public func ready(within timeout: Duration = .seconds(5)) async throws {
        try await withCheckedThrowingContinuation { (ready: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { [connection, frames] state in
                switch state {
                case .ready:
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .cancelled, .failed: frames.finish()
                        default: break
                        }
                    }
                    BridgeListener.receive(from: connection, reader: FrameReader(), into: frames)
                    ready.resume()
                case .waiting(let error), .failed(let error):
                    connection.stateUpdateHandler = nil
                    ready.resume(throwing: error)
                case .cancelled:
                    connection.stateUpdateHandler = nil
                    ready.resume(throwing: CancellationError())
                default:
                    break
                }
            }
            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + .milliseconds(Int(timeout / .milliseconds(1)))) { [connection] in
                if case .ready = connection.state { return }
                connection.cancel()
            }
        }
    }

    public func send(_ frame: Frame) async throws {
        let data = try frame.encoded()
        try await withCheckedThrowingContinuation { (sent: CheckedContinuation<Void, Error>) in
            connection.send(content: data, completion: .contentProcessed { error in
                if let error { sent.resume(throwing: error) } else { sent.resume() }
            })
        }
    }

    public func cancel() {
        frames.finish()
        connection.cancel()
    }
}

#if DEBUG
extension Bridge {
    /// The key debug builds share in place of each TV's own. Anyone with the source
    /// can derive it, so only debug builds hold it.
    public static let developmentKey = SymmetricKey(data: SHA256.hash(data: Data("Northlight development".utf8)))
}
#endif
