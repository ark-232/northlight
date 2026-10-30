import Foundation

public struct Flight: Codable, Sendable, Equatable, Identifiable {
    public var id: String
    /// Callsign where broadcast, otherwise the registration or the ICAO hex.
    public var label: String
    public var type: String?
    /// Feet. Nil when the aircraft is reporting on the ground.
    public var altitudeFeet: Int?
    public var onGround: Bool
    public var groundSpeedKnots: Double?
    public var distanceNM: Double?
    public var track: Double?
    public var latitude: Double?
    public var longitude: Double?
    /// The transponder code.
    public var squawk: String? = nil

    /// What the squawk declares, for the three codes kept for trouble.
    public var emergency: String? {
        switch squawk {
        case "7500": "hijack"
        case "7600": "radio failure"
        case "7700": "emergency"
        default: nil
        }
    }
}

/// ADS-B decoding kept separate from the request so the awkward fields can be
/// regression-tested. `alt_baro` is the trap: it is a number in flight and the
/// **string** "ground" on the ground, which a plain Int decoder would choke on.
public enum FlightParsing {

    struct Aircraft: Decodable {
        var hex: String?
        var flight: String?
        var r: String?
        var t: String?
        var gs: Double?
        var dst: Double?
        var track: Double?
        var lat: Double?
        var lon: Double?
        var category: String?
        var squawk: String?
        var altitudeFeet: Int?
        var onGround: Bool

        enum CodingKeys: String, CodingKey {
            case hex, flight, r, t, gs, dst, track, lat, lon, category, squawk
            case altBaro = "alt_baro"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            hex = try? c.decode(String.self, forKey: .hex)
            flight = try? c.decode(String.self, forKey: .flight)
            r = try? c.decode(String.self, forKey: .r)
            t = try? c.decode(String.self, forKey: .t)
            gs = try? c.decode(Double.self, forKey: .gs)
            dst = try? c.decode(Double.self, forKey: .dst)
            track = try? c.decode(Double.self, forKey: .track)
            lat = try? c.decode(Double.self, forKey: .lat)
            lon = try? c.decode(Double.self, forKey: .lon)
            category = try? c.decode(String.self, forKey: .category)
            squawk = try? c.decode(String.self, forKey: .squawk)

            if let feet = try? c.decode(Double.self, forKey: .altBaro) {
                altitudeFeet = Int(feet)
                onGround = false
            } else if let text = try? c.decode(String.self, forKey: .altBaro) {
                altitudeFeet = nil
                onGround = text.lowercased() == "ground"
            } else {
                altitudeFeet = nil
                onGround = false
            }
        }
    }

    struct Payload: Decodable {
        var ac: [Aircraft]?
    }

    public static func flights(from data: Data) throws -> [Flight] {
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw FeedError.decode("unrecognised ADS-B payload")
        }
        let aircraft = payload.ac ?? []

        return aircraft.compactMap { a -> Flight? in
            // Emitter category C is surface vehicles and obstacles; TWR and GND are
            // the type codes for towers and ground vehicles that carry transponders.
            if a.category?.hasPrefix("C") == true || ["TWR", "GND"].contains(a.t) { return nil }
            let callsign = a.flight?.trimmingCharacters(in: .whitespaces)
            let registration = a.r?.trimmingCharacters(in: .whitespaces)
            let label = [callsign, registration, a.hex]
                .compactMap { $0 }
                .first { !$0.isEmpty }
            guard let label, let id = a.hex ?? label as String? else { return nil }

            return Flight(
                id: id,
                label: label,
                type: a.t?.isEmpty == false ? a.t : nil,
                altitudeFeet: a.altitudeFeet,
                onGround: a.onGround,
                groundSpeedKnots: a.gs,
                distanceNM: a.dst,
                track: a.track,
                latitude: a.lat,
                longitude: a.lon,
                squawk: a.squawk
            )
        }
        // Airborne first, then nearest — a dashboard cares about what is flying.
        .sorted {
            if $0.onGround != $1.onGround { return !$0.onGround }
            return ($0.distanceNM ?? .greatestFiniteMagnitude) < ($1.distanceNM ?? .greatestFiniteMagnitude)
        }
    }
}

extension HTTP {
    /// adsb.fi's open data: keyless, one request a second, for personal and
    /// non-commercial use, cited with a link. It reports what volunteer receivers
    /// happen to be hearing, so coverage is partial by nature and an empty list is a
    /// normal result, not an error.
    public func flights(lat: Double, lon: Double, radiusNM: Int = 50) async throws -> [Flight] {
        let url = makeURL("https://opendata.adsb.fi/api/v3/lat/\(lat)/lon/\(lon)/dist/\(radiusNM)")
        let body = try await data(url, accept: "application/json")
        return try FlightParsing.flights(from: body)
    }
}
