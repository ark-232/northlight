import Foundation

/// The Sun's weather as it reaches the Earth: the solar wind at L1, the GOES X-ray
/// class now and the latest flare, and NOAA's radio, radiation and geomagnetic scales.
public struct SpaceWeather: Codable, Sendable, Equatable {
    public struct Wind: Codable, Sendable, Equatable {
        /// Proton speed, km/s.
        public var speed: Double?
        /// The field's north-south component in GSM, nT. Southward (negative) is
        /// what lets the solar wind into the magnetosphere.
        public var bz: Double?
        public var at: Date?

        public init(speed: Double?, bz: Double?, at: Date?) {
            self.speed = speed; self.bz = bz; self.at = at
        }
    }

    public struct XRay: Codable, Sendable, Equatable {
        public var time: Date
        /// 0.1 to 0.8 nm flux, W/m².
        public var flux: Double

        public init(time: Date, flux: Double) { self.time = time; self.flux = flux }
    }

    public struct Flare: Codable, Sendable, Equatable {
        public var peakClass: String
        public var peak: Date
        /// Nil while the flare is still under way.
        public var end: Date?

        public init(peakClass: String, peak: Date, end: Date?) {
            self.peakClass = peakClass; self.peak = peak; self.end = end
        }
    }

    /// Today's observed levels, 0 to 5 each.
    public struct Scales: Codable, Sendable, Equatable {
        public var r: Int, s: Int, g: Int
        public init(r: Int, s: Int, g: Int) { self.r = r; self.s = s; self.g = g }
    }

    public var wind: Wind
    /// The flare class of the X-ray flux now, as SWPC computes it.
    public var currentClass: String?
    public var flare: Flare?
    public var scales: Scales

    public init(wind: Wind, currentClass: String?, flare: Flare?, scales: Scales) {
        self.wind = wind; self.currentClass = currentClass; self.flare = flare; self.scales = scales
    }

    /// A flux as a flare class: the letter for its decade from A (10⁻⁸ W/m²) to X
    /// (10⁻⁴), and the multiplier to one decimal.
    public static func flareClass(flux: Double) -> String {
        let letters: [(String, Double)] = [("A", 1e-8), ("B", 1e-7), ("C", 1e-6), ("M", 1e-5), ("X", 1e-4)]
        var index = letters.lastIndex { flux >= $0.1 } ?? 0
        var multiplier = (flux / letters[index].1 * 10).rounded() / 10
        if multiplier >= 10, index < letters.count - 1 {
            index += 1
            multiplier = (flux / letters[index].1 * 10).rounded() / 10
        }
        return letters[index].0 + String(format: "%.1f", multiplier)
    }
}

public enum SpaceWeatherParsing {
    private struct SpeedRow: Decodable {
        var time_tag: String
        var proton_speed: Double?
    }

    private struct FieldRow: Decodable {
        var time_tag: String
        var bz_gsm: Double?
    }

    private struct XRayRow: Decodable {
        var time_tag: String
        var flux: Double?
        var energy: String
    }

    private struct FlareRow: Decodable {
        var current_class: String?
        var max_class: String?
        var max_time: String?
        var end_time: String?
    }

    private struct ScalesDay: Decodable {
        struct Level: Decodable { var Scale: String? }
        var R: Level, S: Level, G: Level
    }

    /// SWPC writes these times in UTC, some without the zone.
    static func date(_ string: String) -> Date? {
        try? Date(string.hasSuffix("Z") ? string : string + "Z", strategy: .iso8601)
    }

    /// SWPC's summaries hold one reading each, rounded to whole numbers.
    public static func wind(speed: Data, field: Data) throws -> SpaceWeather.Wind {
        let speed = try decodeFeed([SpeedRow].self, from: speed).first
        let field = try decodeFeed([FieldRow].self, from: field).first
        guard speed?.proton_speed != nil || field?.bz_gsm != nil else { throw FeedError.decode("no solar wind readings") }
        let times = [speed?.time_tag, field?.time_tag].compactMap { $0 }.compactMap(date)
        return SpaceWeather.Wind(speed: speed?.proton_speed, bz: field?.bz_gsm, at: times.max())
    }

    public static func xrays(from data: Data) throws -> [SpaceWeather.XRay] {
        try decodeFeed([XRayRow].self, from: data)
            .filter { $0.energy == "0.1-0.8nm" }
            .compactMap { row in
                guard let flux = row.flux, flux > 0, let time = date(row.time_tag) else { return nil }
                return SpaceWeather.XRay(time: time, flux: flux)
            }
            .sorted { $0.time < $1.time }
    }

    public static func currentClass(from data: Data) throws -> String? {
        try decodeFeed([FlareRow].self, from: data).first?.current_class
    }

    public static func flare(from data: Data) throws -> SpaceWeather.Flare? {
        guard let row = try decodeFeed([FlareRow].self, from: data).first,
              let peakClass = row.max_class, let peak = row.max_time.flatMap(date)
        else { return nil }
        return SpaceWeather.Flare(peakClass: peakClass, peak: peak, end: row.end_time.flatMap(date))
    }

    /// Key "0" is today's observed levels; the others are forecasts.
    public static func scales(from data: Data) throws -> SpaceWeather.Scales {
        guard let today = try decodeFeed([String: ScalesDay].self, from: data)["0"] else {
            throw FeedError.decode("no observed scales")
        }
        func level(_ l: ScalesDay.Level) -> Int { l.Scale.flatMap(Int.init) ?? 0 }
        return SpaceWeather.Scales(r: level(today.R), s: level(today.S), g: level(today.G))
    }
}

extension HTTP {
    private static let swpc = "https://services.swpc.noaa.gov/"

    /// NOAA SWPC, keyless: four small files, under 1 KB of JSON together.
    public func spaceWeather() async throws -> SpaceWeather {
        async let speed = data(makeURL(Self.swpc + "products/summary/solar-wind-speed.json"), accept: "application/json")
        async let field = data(makeURL(Self.swpc + "products/summary/solar-wind-mag-field.json"), accept: "application/json")
        async let flares = data(makeURL(Self.swpc + "json/goes/primary/xray-flares-latest.json"), accept: "application/json")
        async let scales = data(makeURL(Self.swpc + "products/noaa-scales.json"), accept: "application/json")
        let flareData = try await flares
        return SpaceWeather(wind: try SpaceWeatherParsing.wind(speed: try await speed, field: try await field),
                            currentClass: try? SpaceWeatherParsing.currentClass(from: flareData),
                            flare: try? SpaceWeatherParsing.flare(from: flareData),
                            scales: try SpaceWeatherParsing.scales(from: try await scales))
    }

    /// Six hours of GOES X-ray flux, about 26 KB compressed, for the large widget's chart.
    public func xrays() async throws -> [SpaceWeather.XRay] {
        try SpaceWeatherParsing.xrays(from: await data(makeURL(Self.swpc + "json/goes/primary/xrays-6-hour.json"), accept: "application/json"))
    }
}
