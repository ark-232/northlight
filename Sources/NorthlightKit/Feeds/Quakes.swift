import Foundation

public struct Quake: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    public var magnitude: Double
    public var place: String
    public var time: Date
    public var depthKm: Double?
    public var latitude: Double? = nil
    public var longitude: Double? = nil
}

private struct QuakePayload: Decodable {
    var features: [Feature]

    struct Feature: Decodable {
        var id: String?
        var properties: Properties
        var geometry: Geometry?

        struct Properties: Decodable {
            var mag: Double?
            var place: String?
            /// Milliseconds since epoch.
            var time: Double?
        }

        struct Geometry: Decodable {
            var coordinates: [Double]?
        }
    }
}

extension HTTP {
    /// USGS FDSN event query within a circle around a point. Keyless.
    public func quakes(lat: Double, lon: Double, radiusKM: Double, minMagnitude: Double,
                       days: Int = 7, now: Date = Date()) async throws -> [Quake] {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        iso.timeZone = TimeZone(identifier: "UTC")

        let url = makeURL("https://earthquake.usgs.gov/fdsnws/event/1/query", [
            "format": "geojson",
            "starttime": iso.string(from: now.addingTimeInterval(-Double(days) * 86_400)),
            "latitude": String(lat),
            "longitude": String(lon),
            "maxradiuskm": String(radiusKM),
            "minmagnitude": String(minMagnitude),
            "orderby": "time",
            "limit": "40",
        ])

        return try QuakeParsing.quakes(from: await data(url, accept: "application/json"))
    }
}

public enum QuakeParsing {
    public static func quakes(from data: Data) throws -> [Quake] {
        try decodeFeed(QuakePayload.self, from: data).features.compactMap { f in
            guard let mag = f.properties.mag, let ms = f.properties.time else { return nil }
            // GeoJSON orders a point longitude, latitude, depth.
            let point = f.geometry?.coordinates
            return Quake(
                id: f.id ?? "\(ms)",
                magnitude: mag,
                place: f.properties.place ?? "Unknown location",
                time: Date(timeIntervalSince1970: ms / 1000),
                depthKm: point?[safe: 2],
                latitude: point?[safe: 1],
                longitude: point?[safe: 0]
            )
        }
    }
}
