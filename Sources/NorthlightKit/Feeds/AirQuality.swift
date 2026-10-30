import Foundation

public struct AirQuality: Codable, Sendable, Equatable {
    public var usAQI: Int?
    public var pm25: Double?
    public var pm10: Double?

    /// US EPA AQI bands, with the label and a severity rank for colouring.
    public var band: (label: String, rank: Int) {
        guard let usAQI else { return ("—", 0) }
        switch usAQI {
        case ..<51: return ("Good", 0)
        case ..<101: return ("Moderate", 1)
        case ..<151: return ("Unhealthy for sensitive groups", 2)
        case ..<201: return ("Unhealthy", 3)
        case ..<301: return ("Very unhealthy", 4)
        default: return ("Hazardous", 5)
        }
    }
}

private struct AirQualityPayload: Decodable {
    var current: Current?

    struct Current: Decodable {
        var us_aqi: Int?
        var pm2_5: Double?
        var pm10: Double?
    }
}

extension HTTP {
    /// Open-Meteo's air-quality API, keyless, on its own host. Matters here mainly
    /// for wildfire smoke, the air-quality event most likely to change plans.
    public func airQuality(lat: Double, lon: Double) async throws -> AirQuality {
        let url = makeURL("https://air-quality-api.open-meteo.com/v1/air-quality", [
            "latitude": String(lat),
            "longitude": String(lon),
            "current": "us_aqi,pm2_5,pm10",
            "timezone": "auto",
        ])
        let raw = try await json(AirQualityPayload.self, from: url)
        return AirQuality(
            usAQI: raw.current?.us_aqi,
            pm25: raw.current?.pm2_5,
            pm10: raw.current?.pm10
        )
    }
}
