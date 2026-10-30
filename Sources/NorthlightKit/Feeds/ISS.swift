import Foundation

/// Where the International Space Station is at one instant.
public struct ISSFix: Codable, Sendable, Equatable {
    public var latitude: Double
    public var longitude: Double
    public var altitudeKM: Double
    public var velocityKMH: Double
    /// Whether the station is in sunlight rather than the Earth's shadow.
    public var sunlit: Bool
    public var time: Date

    public init(latitude: Double, longitude: Double, altitudeKM: Double, velocityKMH: Double, sunlit: Bool, time: Date) {
        self.latitude = latitude; self.longitude = longitude; self.altitudeKM = altitudeKM
        self.velocityKMH = velocityKMH; self.sunlit = sunlit; self.time = time
    }
}

/// The station's recent fixes, oldest first: about one orbit, so the map draws a
/// full ground track once the widget has watched for that long.
public struct ISSTrack: Codable, Sendable, Equatable {
    /// One orbit is about 93 minutes.
    public static let span: TimeInterval = 95 * 60
    /// A longer silence than this between fixes is not drawn as a line.
    static let gap: TimeInterval = 120

    public private(set) var fixes: [ISSFix] = []

    public init(fixes: [ISSFix] = []) { self.fixes = fixes }

    public var latest: ISSFix? { fixes.last }

    public func adding(_ fix: ISSFix) -> ISSTrack {
        guard fix.time > (fixes.last?.time ?? .distantPast) else { return self }
        return ISSTrack(fixes: (fixes + [fix]).filter { fix.time.timeIntervalSince($0.time) <= Self.span })
    }

    /// Runs of fixes to draw as lines, broken where the track crosses the date line
    /// or the feed went quiet.
    public var segments: [[ISSFix]] {
        var runs: [[ISSFix]] = []
        for fix in fixes {
            if let last = runs.last?.last, abs(fix.longitude - last.longitude) < 180, fix.time.timeIntervalSince(last.time) <= Self.gap {
                runs[runs.count - 1].append(fix)
            } else {
                runs.append([fix])
            }
        }
        return runs
    }
}

public enum ISSParsing {
    private struct Payload: Decodable {
        var latitude: Double
        var longitude: Double
        var altitude: Double
        var velocity: Double
        var visibility: String
        var timestamp: Double
    }

    public static func fix(from data: Data) throws -> ISSFix {
        let p = try decodeFeed(Payload.self, from: data)
        return ISSFix(latitude: p.latitude, longitude: p.longitude, altitudeKM: p.altitude, velocityKMH: p.velocity,
                      sunlit: p.visibility == "daylight", time: Date(timeIntervalSince1970: p.timestamp))
    }
}

extension HTTP {
    /// wheretheiss.at, keyless, about one request a second allowed. 25544 is the
    /// station's NORAD catalog number.
    public func iss() async throws -> ISSFix {
        try ISSParsing.fix(from: await data(makeURL("https://api.wheretheiss.at/v1/satellites/25544"), accept: "application/json"))
    }
}
