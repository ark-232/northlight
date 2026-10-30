import Foundation

public struct Weather: Codable, Sendable, Equatable {
    public var temperature: Measurement<UnitTemperature>
    public var apparent: Measurement<UnitTemperature>
    public var code: Int
    public var windSpeed: Measurement<UnitSpeed>
    public var humidity: Int
    public var isDay: Bool
    /// Percent of the sky covered.
    public var cloudCover: Int?

    /// Today onward.
    public var days: [Day]

    public var snowDepth: Measurement<UnitLength>?

    public struct Day: Codable, Sendable, Equatable, Identifiable {
        public var date: Date
        public var high: Measurement<UnitTemperature>
        public var low: Measurement<UnitTemperature>
        public var code: Int
        public var precipitationChance: Int
        public var snowfall: Measurement<UnitLength>
        public var id: Date { date }
    }

    /// WMO weather interpretation code → a short label and an SF Symbol.
    public var condition: (label: String, symbol: String) { Weather.describe(code, isDay: isDay) }

    public static func describe(_ code: Int, isDay: Bool) -> (label: String, symbol: String) {
        switch code {
        case 0: return ("Clear", isDay ? "sun.max.fill" : "moon.stars.fill")
        case 1: return ("Mostly clear", isDay ? "sun.min.fill" : "moon.fill")
        case 2: return ("Partly cloudy", isDay ? "cloud.sun.fill" : "cloud.moon.fill")
        case 3: return ("Overcast", "cloud.fill")
        case 45, 48: return ("Fog", "cloud.fog.fill")
        case 51, 53, 55: return ("Drizzle", "cloud.drizzle.fill")
        case 56, 57: return ("Freezing drizzle", "cloud.sleet.fill")
        case 61, 63, 65: return ("Rain", "cloud.rain.fill")
        case 66, 67: return ("Freezing rain", "cloud.sleet.fill")
        case 71, 73, 75: return ("Snow", "cloud.snow.fill")
        case 77: return ("Snow grains", "cloud.snow.fill")
        case 80, 81, 82: return ("Showers", "cloud.heavyrain.fill")
        case 85, 86: return ("Snow showers", "cloud.snow.fill")
        case 95: return ("Thunderstorm", "cloud.bolt.rain.fill")
        case 96, 99: return ("Thunderstorm, hail", "cloud.bolt.rain.fill")
        default: return ("—", "questionmark.circle")
        }
    }
}

enum WeatherParsing {
    struct Payload: Decodable {
        var current: Current
        var daily: Daily
        var hourly: Hourly?

        struct Current: Decodable {
            var temperature_2m: Double
            var apparent_temperature: Double
            var weather_code: Int
            var wind_speed_10m: Double
            var relative_humidity_2m: Int
            var is_day: Int
            var cloud_cover: Int?
        }

        struct Daily: Decodable {
            var time: [String]
            var temperature_2m_max: [Double]
            var temperature_2m_min: [Double]
            var weather_code: [Int]
            var precipitation_probability_max: [Int?]
            var snowfall_sum: [Double?]
        }

        struct Hourly: Decodable {
            var snow_depth: [Double?]?
        }
    }

    /// Days are bucketed in `zone`, the place's, so the forecast's days are the
    /// dashboard's days, starting today. Values keep Open-Meteo's default units,
    /// confirmed against the live response: Celsius, km/h, snowfall in centimetres
    /// and snow depth in metres.
    static func weather(from data: Data, timeZone zone: TimeZone) throws -> Weather {
        let raw = try decodeFeed(Payload.self, from: data)

        let dayFmt = DateFormatter()
        dayFmt.locale = Locale(identifier: "en_US_POSIX")
        dayFmt.dateFormat = "yyyy-MM-dd"
        dayFmt.timeZone = zone

        var all: [Weather.Day] = []
        for (i, dayString) in raw.daily.time.enumerated() {
            guard let date = dayFmt.date(from: dayString) else { continue }
            all.append(Weather.Day(
                date: date,
                high: Measurement(value: raw.daily.temperature_2m_max[safe: i] ?? 0, unit: .celsius),
                low: Measurement(value: raw.daily.temperature_2m_min[safe: i] ?? 0, unit: .celsius),
                code: raw.daily.weather_code[safe: i] ?? 0,
                precipitationChance: raw.daily.precipitation_probability_max[safe: i].flatMap { $0 } ?? 0,
                snowfall: Measurement(value: raw.daily.snowfall_sum[safe: i].flatMap { $0 } ?? 0, unit: .centimeters)
            ))
        }

        return Weather(
            temperature: Measurement(value: raw.current.temperature_2m, unit: .celsius),
            apparent: Measurement(value: raw.current.apparent_temperature, unit: .celsius),
            code: raw.current.weather_code,
            windSpeed: Measurement(value: raw.current.wind_speed_10m, unit: .kilometersPerHour),
            humidity: raw.current.relative_humidity_2m,
            isDay: raw.current.is_day == 1,
            cloudCover: raw.current.cloud_cover,
            days: all,
            snowDepth: raw.hourly?.snow_depth?.first.flatMap { $0 }.map { Measurement(value: $0, unit: .meters) }
        )
    }
}

extension HTTP {
    /// Open-Meteo. Keyless, and metric: the views choose the units.
    public func weather(lat: Double, lon: Double, timeZone zone: TimeZone) async throws -> Weather {
        let url = makeURL("https://api.open-meteo.com/v1/forecast", [
            "latitude": String(lat),
            "longitude": String(lon),
            "current": "temperature_2m,apparent_temperature,weather_code,wind_speed_10m,relative_humidity_2m,is_day,cloud_cover",
            "daily": "temperature_2m_max,temperature_2m_min,weather_code,precipitation_probability_max,snowfall_sum",
            "hourly": "snow_depth",
            "forecast_hours": "1",
            "forecast_days": "7",
            "timezone": zone.identifier,
        ])

        return try WeatherParsing.weather(from: try await data(url, accept: "application/json"), timeZone: zone)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
