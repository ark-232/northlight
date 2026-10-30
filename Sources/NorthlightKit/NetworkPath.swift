import Darwin
import Network

/// The TV's connection, as the Network widget shows it.
public struct NetworkPath: Codable, Equatable, Sendable {
    public enum Link: String, Codable, Sendable { case ethernet, wifi, other }
    public enum Quality: String, Codable, Sendable { case good, moderate, minimal }

    /// Nil when there is no connection.
    public var link: Link?
    /// Nil when the system does not say.
    public var quality: Quality?
    /// Cellular, a phone's hotspot, or Low Data Mode, where automatic speed tests stay off.
    public var isMetered: Bool
    /// The router's address, which the latency monitor probes.
    public var gateway: String?
    /// This Apple TV's own address on the link.
    public var address: String?

    /// Why a speed test will not run here, if it will not.
    public var speedTestRefusal: String? {
        isMetered ? "This network is metered or in Low Data Mode. Speed tests run on unmetered networks only." : nil
    }

    public init(link: Link?, quality: Quality?, isMetered: Bool = false, gateway: String? = nil, address: String? = nil) {
        self.link = link
        self.quality = quality
        self.isMetered = isMetered
        self.gateway = gateway
        self.address = address
    }

    public init(_ path: NWPath) {
        link = switch path.status {
        case .satisfied: path.usesInterfaceType(.wiredEthernet) ? .ethernet : path.usesInterfaceType(.wifi) ? .wifi : .other
        default: nil
        }
        quality = switch path.linkQuality {
        case .good: .good
        case .moderate: .moderate
        case .minimal: .minimal
        default: nil
        }
        isMetered = path.isExpensive || path.isConstrained
        let hosts = path.gateways.compactMap { endpoint -> NWEndpoint.Host? in
            if case .hostPort(let host, _) = endpoint { host } else { nil }
        }
        gateway = (hosts.first { if case .ipv4 = $0 { true } else { false } } ?? hosts.first).map { "\($0)" }
        address = path.availableInterfaces.first.flatMap { Self.ipv4Address(of: $0.name) }
    }

    private static func ipv4Address(of interface: String) -> String? {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return nil }
        defer { freeifaddrs(list) }
        for entry in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard String(cString: entry.pointee.ifa_name) == interface,
                  let address = entry.pointee.ifa_addr, address.pointee.sa_family == UInt8(AF_INET)
            else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0
            else { continue }
            return String(cString: host)
        }
        return nil
    }
}
