import Foundation

/// The sun's position, from the NOAA solar calculator's algorithm: good to about a
/// minute of time and a tenth of a degree.
public enum Solar {
    public enum Day: Equatable, Sendable {
        case risesAndSets(sunrise: Date, sunset: Date)
        case alwaysUp
        case alwaysDown

        public var length: TimeInterval {
            switch self {
            case .risesAndSets(let sunrise, let sunset): sunset.timeIntervalSince(sunrise)
            case .alwaysUp: 86_400
            case .alwaysDown: 0
            }
        }
    }

    /// Degrees of the sun's center above the horizon, without refraction.
    public static func elevation(at date: Date, latitude: Double, longitude: Double) -> Double {
        let sun = position(at: date)
        let minutesUTC = mod(date.timeIntervalSince1970 / 60, 1_440)
        let hourAngle = radians(mod(minutesUTC + sun.equationOfTime + 4 * longitude, 1_440) / 4 - 180)
        let φ = radians(latitude), δ = radians(sun.declination)
        let cosZenith = sin(φ) * sin(δ) + cos(φ) * cos(δ) * cos(hourAngle)
        return 90 - degrees(acos(min(1, max(-1, cosZenith))))
    }

    /// The lowest the sun gets on the day around `date`, at solar midnight.
    public static func lowestElevation(around date: Date, latitude: Double) -> Double {
        abs(latitude + position(at: date).declination) - 90
    }

    /// Sunrise and sunset on the place's local day containing `date`, for the sun's
    /// upper limb with standard refraction (-0.833 degrees).
    public static func day(containing date: Date, latitude: Double, longitude: Double, calendar: Calendar) -> Day {
        let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!
        let atNoon = cosHorizonHourAngle(declination: position(at: noon).declination, latitude: latitude)
        if atNoon > 1 { return .alwaysDown }
        if atNoon < -1 { return .alwaysUp }
        // Each event is solved again with the sun where it stands at the first answer:
        // near the poles the sun's declination moves an event by many minutes.
        func event(_ side: Double) -> Date {
            let first = horizonCrossing(side, around: noon, sunAt: noon, latitude: latitude, longitude: longitude)
            return horizonCrossing(side, around: noon, sunAt: first, latitude: latitude, longitude: longitude)
        }
        return .risesAndSets(sunrise: event(-1), sunset: event(1))
    }

    /// When the sun's upper limb meets the horizon before (`side` -1) or after (+1)
    /// the solar noon nearest local `noon`, with the sun's position taken at `sunAt`.
    private static func horizonCrossing(_ side: Double, around noon: Date, sunAt: Date,
                                        latitude: Double, longitude: Double) -> Date {
        let sun = position(at: sunAt)
        let cosHourAngle = cosHorizonHourAngle(declination: sun.declination, latitude: latitude)
        let halfDay = 4 * degrees(acos(min(1, max(-1, cosHourAngle))))
        // Minutes from local noon to the nearest solar noon, which can sit on another
        // UTC day: in Auckland's summer, local noon is 23:00 UTC the day before.
        var toSolarNoon = mod(720 - 4 * longitude - sun.equationOfTime - mod(noon.timeIntervalSince1970 / 60, 1_440), 1_440)
        if toSolarNoon > 720 { toSolarNoon -= 1_440 }
        return noon.addingTimeInterval((toSolarNoon + side * halfDay) * 60)
    }

    /// Above 1 the sun stays below the horizon all day; below -1 it stays above.
    private static func cosHorizonHourAngle(declination: Double, latitude: Double) -> Double {
        let φ = radians(latitude), δ = radians(declination)
        return (cos(radians(90.833)) - sin(φ) * sin(δ)) / (cos(φ) * cos(δ))
    }

    /// How far to dim the display, 0 to 1. Dimming starts when the sun sinks below
    /// max(-6, the day's lowest + 1) degrees and is full 6 degrees lower or at the
    /// day's lowest, whichever comes first. At 61 N in June the sun never reaches
    /// -6, so a fixed threshold would leave the room lit all night.
    public static func nightDim(elevation: Double, lowest: Double) -> Double {
        let start = max(-6, lowest + 1)
        let full = max(start - 6, lowest)
        guard elevation < start else { return 0 }
        return min(1, (start - elevation) / (start - full))
    }

    public static func nightDim(at date: Date, latitude: Double, longitude: Double) -> Double {
        nightDim(elevation: elevation(at: date, latitude: latitude, longitude: longitude),
                 lowest: lowestElevation(around: date, latitude: latitude))
    }

    /// Declination and the equation of time (minutes) at an instant.
    private static func position(at date: Date) -> (declination: Double, equationOfTime: Double) {
        let julianDay = date.timeIntervalSince1970 / 86_400 + 2_440_587.5
        let t = (julianDay - 2_451_545) / 36_525
        let meanLongitude = mod(280.46646 + t * (36_000.76983 + t * 0.0003032), 360)
        let anomaly = radians(357.52911 + t * (35_999.05029 - 0.0001537 * t))
        let eccentricity = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let center = sin(anomaly) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * anomaly) * (0.019993 - 0.000101 * t)
            + sin(3 * anomaly) * 0.000289
        let omega = radians(125.04 - 1_934.136 * t)
        let apparentLongitude = radians(meanLongitude + center - 0.00569 - 0.00478 * sin(omega))
        let meanObliquity = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let obliquity = radians(meanObliquity + 0.00256 * cos(omega))

        let declination = degrees(asin(sin(obliquity) * sin(apparentLongitude)))
        let y = pow(tan(obliquity / 2), 2)
        let l0 = radians(meanLongitude)
        let equationOfTime = 4 * degrees(
            y * sin(2 * l0)
            - 2 * eccentricity * sin(anomaly)
            + 4 * eccentricity * y * sin(anomaly) * cos(2 * l0)
            - 0.5 * y * y * sin(4 * l0)
            - 1.25 * eccentricity * eccentricity * sin(2 * anomaly))
        return (declination, equationOfTime)
    }

    private static func mod(_ value: Double, _ modulus: Double) -> Double {
        let r = value.truncatingRemainder(dividingBy: modulus)
        return r < 0 ? r + modulus : r
    }

    private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
