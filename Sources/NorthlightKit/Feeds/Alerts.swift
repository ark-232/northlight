import Foundation

public struct WeatherAlert: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var event: String
    public var headline: String?
    public var severity: String
    /// When the hazard ends. NWS often leaves it null.
    public var ends: Date?
    /// When the message expires. NWS always sends it, so it bounds an alert whose
    /// `ends` is null.
    public var expires: Date?

    /// NWS severity ladder, collapsed to a sort rank so the worst shows first.
    public var rank: Int {
        switch severity.lowercased() {
        case "extreme": return 0
        case "severe": return 1
        case "moderate": return 2
        case "minor": return 3
        default: return 4
        }
    }

    /// An alert counts until its hazard ends, or without an end until its message
    /// expires. A cached alert outlives both, so this is checked at render time.
    public func isActive(at now: Date) -> Bool {
        (ends ?? expires).map { $0 > now } ?? true
    }
}

/// NWS decoding kept apart from the request so it can be regression-tested.
public enum AlertParsing {
    struct Payload: Decodable {
        var features: [Feature]

        struct Feature: Decodable {
            var id: String?
            var properties: Properties

            struct Properties: Decodable {
                var event: String?
                var headline: String?
                var severity: String?
                var ends: String?
                var expires: String?
            }
        }
    }

    public static func alerts(from data: Data) throws -> [WeatherAlert] {
        let raw = try decodeFeed(Payload.self, from: data)
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        return raw.features
            .compactMap { f -> WeatherAlert? in
                guard let event = f.properties.event else { return nil }
                return WeatherAlert(
                    id: f.id ?? event,
                    event: event,
                    headline: f.properties.headline,
                    severity: f.properties.severity ?? "Unknown",
                    ends: f.properties.ends.flatMap { iso.date(from: $0) },
                    expires: f.properties.expires.flatMap { iso.date(from: $0) }
                )
            }
            .sorted { $0.rank < $1.rank }
    }
}

extension HTTP {
    /// api.weather.gov active alerts for a point. Keyless, but it rejects requests
    /// without a User-Agent naming the app and a contact — that is set in HTTP.init.
    public func alerts(lat: Double, lon: Double) async throws -> [WeatherAlert] {
        let url = makeURL("https://api.weather.gov/alerts/active", [
            "point": "\(lat),\(lon)",
        ])
        return try AlertParsing.alerts(from: try await data(url, accept: "application/json"))
    }
}
