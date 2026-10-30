import Foundation

/// An orbital launch on Launch Library 2's schedule.
public struct Launch: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var mission: String
    public var rocket: String
    public var provider: String
    public var pad: String
    public var location: String
    /// No earlier than: the target time, as exact as `precision` says.
    public var net: Date
    /// LL2's abbreviation for how exact `net` is: SEC, MIN, HR, DAY, MON and coarser.
    public var precision: String?
    /// LL2's short status: Go, TBC, TBD, Hold, In Flight, Success, Failure.
    public var status: String

    public init(id: String, mission: String, rocket: String, provider: String, pad: String, location: String,
                net: Date, precision: String?, status: String) {
        self.id = id; self.mission = mission; self.rocket = rocket; self.provider = provider; self.pad = pad
        self.location = location; self.net = net; self.precision = precision; self.status = status
    }

    /// Whether `net` names a minute rather than an hour, a day or a month.
    public var isExact: Bool { precision == nil || precision == "SEC" || precision == "MIN" }

    /// The schedule without launches that have flown or slipped past an hour ago
    /// without word. LL2 keeps a launch "upcoming" for a while after it flies.
    public static func upcoming(_ launches: [Launch], at now: Date) -> [Launch] {
        launches.filter { !["Success", "Failure", "Partial Failure"].contains($0.status) && $0.net > now.addingTimeInterval(-3_600) }
    }

    /// Days and hours far out, hours and minutes within a day, minutes and seconds
    /// within the hour; T+ once the time has passed.
    public static func countdown(_ seconds: TimeInterval) -> String {
        let sign = seconds < 0 ? "T+" : "T−"
        let s = Int(abs(seconds))
        switch s {
        case 86_400...: return "\(sign)\(s / 86_400) d \(s % 86_400 / 3_600) h"
        case 3_600...: return "\(sign)\(s / 3_600) h \(s % 3_600 / 60) m"
        default: return sign + String(format: "%02d:%02d", s / 60, s % 60)
        }
    }
}

public enum LaunchParsing {
    private struct Payload: Decodable {
        var results: [Row]
    }

    private struct Row: Decodable {
        struct Named: Decodable { var name: String? }
        struct Status: Decodable { var abbrev: String? }
        struct Precision: Decodable { var abbrev: String? }
        struct Rocket: Decodable { var configuration: Named? }
        struct Pad: Decodable { var name: String?; var location: Named? }

        var id: String
        var name: String
        var status: Status?
        var net: String?
        var net_precision: Precision?
        var launch_service_provider: Named?
        var rocket: Rocket?
        var mission: Named?
        var pad: Pad?
    }

    public static func launches(from data: Data) throws -> [Launch] {
        try decodeFeed(Payload.self, from: data).results.compactMap { row in
            guard let net = row.net.flatMap({ try? Date($0, strategy: .iso8601) }) else { return nil }
            // LL2 names a launch "Rocket | Mission".
            let parts = row.name.components(separatedBy: " | ")
            return Launch(id: row.id, mission: row.mission?.name ?? parts.last ?? row.name,
                          rocket: row.rocket?.configuration?.name ?? parts.first ?? "",
                          provider: row.launch_service_provider?.name ?? "", pad: row.pad?.name ?? "",
                          location: row.pad?.location?.name ?? "", net: net, precision: row.net_precision?.abbrev,
                          status: row.status?.abbrev ?? "TBD")
        }
    }
}

extension HTTP {
    /// The Space Devs' Launch Library 2, keyless at 15 requests an hour per address.
    public func launches() async throws -> [Launch] {
        try LaunchParsing.launches(from: await data(makeURL("https://ll.thespacedevs.com/2.3.0/launches/upcoming/", ["limit": "8"]),
                                                    accept: "application/json"))
    }
}
