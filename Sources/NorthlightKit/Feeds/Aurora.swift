import Foundation

public struct Aurora: Codable, Sendable, Equatable {
    /// Planetary K-index, 0–9. Above roughly 5 is a geomagnetic storm.
    public var kp: Double
    public var kpObserved: Date?
    /// OVATION local probability of visible aurora, 0–100, for the configured point.
    public var localProbability: Int?
    public var forecastTime: Date?

    public var activityLabel: String {
        switch kp {
        case ..<2: return "Quiet"
        case ..<3: return "Unsettled"
        case ..<4: return "Active"
        case ..<5: return "Minor storm"
        case ..<6: return "Moderate storm"
        case ..<7: return "Strong storm"
        case ..<8: return "Severe storm"
        default: return "Extreme storm"
        }
    }
}

/// Decoding lives apart from the network call so both payload shapes can be
/// regression-tested. SWPC has already changed the K-index product's shape once —
/// it used to be a CSV-style array of string arrays with a header row, and is now
/// an array of objects with a numeric Kp.
public enum AuroraParsing {

    struct KpRow: Decodable {
        var timeTag: String?
        var kp: Double

        enum CodingKeys: String, CodingKey {
            case timeTag = "time_tag"
            case kp = "Kp"
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.timeTag = try? c.decode(String.self, forKey: .timeTag)
            // Tolerate either a number or a quoted number, since this field has
            // been both.
            if let d = try? c.decode(Double.self, forKey: .kp) {
                self.kp = d
            } else if let s = try? c.decode(String.self, forKey: .kp), let d = Double(s) {
                self.kp = d
            } else {
                throw FeedError.decode("K-index row had no readable Kp")
            }
        }
    }

    static let kpDateFormats = [
        "yyyy-MM-dd'T'HH:mm:ss",
        "yyyy-MM-dd HH:mm:ss",
    ]

    /// Returns the most recent readable K-index reading.
    public static func kp(from data: Data) throws -> (kp: Double, observed: Date?) {
        let rows: [KpRow]
        do {
            rows = try JSONDecoder().decode([KpRow].self, from: data)
        } catch {
            // Fall back to the historical [[String]] form so an endpoint rollback
            // does not blank the tile.
            if let legacy = try? JSONDecoder().decode([[String]].self, from: data) {
                for row in legacy.reversed() where row.count >= 2 {
                    if let value = Double(row[1]) {
                        return (value, parseDate(row[0]))
                    }
                }
            }
            throw FeedError.decode("unrecognised K-index payload")
        }

        guard let latest = rows.last else {
            throw FeedError.decode("K-index payload was empty")
        }
        return (latest.kp, latest.timeTag.flatMap(parseDate))
    }

    static func parseDate(_ string: String) -> Date? {
        let trimmed = string.hasSuffix("Z") ? String(string.dropLast()) : string
        for format in kpDateFormats {
            let fmt = DateFormatter()
            fmt.locale = Locale(identifier: "en_US_POSIX")
            fmt.timeZone = TimeZone(identifier: "UTC")
            fmt.dateFormat = format
            if let date = fmt.date(from: trimmed) { return date }
        }
        return nil
    }

    struct OvationPayload: Decodable {
        var observationTime: String?
        var forecastTime: String?
        /// Each entry is [longitude 0–359, latitude -90–90, probability 0–100].
        var coordinates: [[Double]]

        enum CodingKeys: String, CodingKey {
            case observationTime = "Observation Time"
            case forecastTime = "Forecast Time"
            case coordinates
        }
    }

    /// Nearest grid cell to the point, from a 1-degree global grid.
    public static func localProbability(
        from data: Data,
        lat: Double,
        lon: Double
    ) -> (probability: Int?, forecastTime: Date?) {
        guard let payload = try? JSONDecoder().decode(OvationPayload.self, from: data) else {
            return (nil, nil)
        }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        let forecastTime = payload.forecastTime.flatMap { iso.date(from: $0) }

        let targetLon = lon < 0 ? lon + 360 : lon
        var best: (distance: Double, probability: Double)? = nil
        for point in payload.coordinates where point.count >= 3 {
            let dLon = abs(point[0] - targetLon)
            let dLat = abs(point[1] - lat)
            guard dLon <= 1.5, dLat <= 1.5 else { continue }
            let distance = dLon * dLon + dLat * dLat
            if best == nil || distance < best!.distance {
                best = (distance, point[2])
            }
        }
        guard let best else { return (nil, forecastTime) }
        return (Int(best.probability.rounded()), forecastTime)
    }
}

extension HTTP {
    /// NOAA SWPC. Both endpoints are keyless.
    public func aurora(lat: Double, lon: Double) async throws -> Aurora {
        let kpData = try await data(
            makeURL("https://services.swpc.noaa.gov/products/noaa-planetary-k-index.json"),
            accept: "application/json"
        )
        let reading = try AuroraParsing.kp(from: kpData)

        // OVATION is a ~900 KB global grid. A failure here must not lose the Kp
        // value, which is the more important of the two numbers.
        var probability: Int? = nil
        var forecastTime: Date? = nil
        if let ovationData = try? await data(
            makeURL("https://services.swpc.noaa.gov/json/ovation_aurora_latest.json"),
            accept: "application/json"
        ) {
            let local = AuroraParsing.localProbability(from: ovationData, lat: lat, lon: lon)
            probability = local.probability
            forecastTime = local.forecastTime
        }

        return Aurora(
            kp: reading.kp,
            kpObserved: reading.observed,
            localProbability: probability,
            forecastTime: forecastTime
        )
    }
}
