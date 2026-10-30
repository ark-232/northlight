import Foundation
import Testing
@testable import NorthlightKit

private let reykjavik = (latitude: 64.1466, longitude: -21.9426)
private let oslo = (latitude: 59.9139, longitude: 10.7522)

private func calendar(_ zone: String) -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: zone)!
    return cal
}

private let norway = calendar("Europe/Oslo")
private let utc = calendar("UTC")

private func at(_ cal: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, _ min: Int = 0) -> Date {
    cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

private func minutes(_ date: Date, in cal: Calendar) -> Int {
    let c = cal.dateComponents([.hour, .minute], from: date)
    return c.hour! * 60 + c.minute!
}

private func sunTimes(_ y: Int, _ m: Int, _ d: Int) throws -> (rise: Int, set: Int, length: TimeInterval) {
    let day = Solar.day(containing: at(norway, y, m, d), latitude: oslo.latitude,
                        longitude: oslo.longitude, calendar: norway)
    guard case .risesAndSets(let rise, let set) = day else { throw SolarTestError.noSunrise }
    return (minutes(rise, in: norway), minutes(set, in: norway), set.timeIntervalSince(rise))
}

private enum SolarTestError: Error { case noSunrise }

/// When the sun's center crosses -0.833 degrees going up or down, from
/// `Solar.elevation` sampled each minute for 90 minutes either side of `estimate`.
private func horizonCrossing(near estimate: Date, rising: Bool, latitude: Double, longitude: Double) -> Date? {
    func height(_ t: Date) -> Double { Solar.elevation(at: t, latitude: latitude, longitude: longitude) + 0.833 }
    var t = estimate.addingTimeInterval(-90 * 60)
    var before = height(t)
    for _ in 0..<180 {
        let next = t.addingTimeInterval(60)
        let after = height(next)
        if rising ? (before < 0 && after >= 0) : (before >= 0 && after < 0) {
            return t.addingTimeInterval(60 * before / (before - after))
        }
        (t, before) = (next, after)
    }
    return nil
}

// MARK: - Position

@Test func reykjaviksSolsticeNoonSunStandsAt49Degrees() {
    let noon = at(utc, 2026, 6, 21, 13, 30)
    #expect(abs(Solar.elevation(at: noon, latitude: reykjavik.latitude, longitude: reykjavik.longitude) - 49.3) < 0.3)
}

@Test func theJuneSunAt64NorthNeverSinksBelowMinusSix() {
    // 64.15 + 23.44 - 90: the reason a fixed -6 degree night threshold fails in June.
    #expect(abs(Solar.lowestElevation(around: at(utc, 2026, 6, 21), latitude: 64.15) - -2.41) < 0.05)
}

// MARK: - Sunrise and sunset in the place's own day

// Oslo's clock time by the USNO convention (upper limb, 34' refraction), from
// PyEphem. 3 November and 11 February are near the equation of time's extremes,
// +16 and -14 minutes.
private let usnoDays: [(Int, Int, Int, Int)] = [
    (6, 21, 3 * 60 + 54, 22 * 60 + 44),
    (12, 21, 9 * 60 + 18, 15 * 60 + 12),
    (11, 3, 7 * 60 + 44, 16 * 60 + 16),
    (2, 11, 8 * 60 + 6, 16 * 60 + 58),
]

@Test(arguments: usnoDays)
func osloRisesAndSetsWhenUSNOSays(month: Int, day: Int, rise: Int, set: Int) throws {
    let times = try sunTimes(2026, month, day)
    #expect(abs(times.rise - rise) <= 1)
    #expect(abs(times.set - set) <= 1)
}

@Test(arguments: [(0, 30), (23, 30)])
func everyHourOfADayGivesThatDaysSun(hour: Int, minute: Int) {
    let asked = Solar.day(containing: at(norway, 2026, 11, 3, hour, minute), latitude: oslo.latitude,
                          longitude: oslo.longitude, calendar: norway)
    let atNoon = Solar.day(containing: at(norway, 2026, 11, 3), latitude: oslo.latitude,
                           longitude: oslo.longitude, calendar: norway)
    #expect(asked == atNoon)
}

private func place(_ name: String, _ latitude: Double, _ longitude: Double, _ zone: String) -> Place {
    Place(name: name, latitude: latitude, longitude: longitude, timeZoneIdentifier: zone, countryCode: nil)
}

private let horizonDays: [(Place, Int, Int)] = [
    (place("Reykjavík", 64.1466, -21.9426, "Atlantic/Reykjavik"), 3, 20),
    (place("Auckland in daylight time", -36.8485, 174.7633, "Pacific/Auckland"), 11, 26),
    (place("Kiritimati, UTC+14", 1.8721, -157.4278, "Pacific/Kiritimati"), 7, 1),
    (place("Tromsø before the midnight sun", 69.6492, 18.9553, "Europe/Oslo"), 5, 17),
    (place("Inuvik before the midnight sun", 68.3607, -133.7230, "America/Inuvik"), 5, 15),
    (place("Alert in April", 82.5018, -62.3481, "America/Toronto"), 4, 5),
]

@Test(arguments: horizonDays)
func theSunRisesAndSetsWhereItCrossesTheHorizonOnTheDayAsked(place: Place, month: Int, day: Int) throws {
    let noon = at(place.calendar, 2026, month, day)
    let sun = Solar.day(containing: noon, latitude: place.latitude, longitude: place.longitude, calendar: place.calendar)
    guard case .risesAndSets(let rise, let set) = sun else {
        Issue.record("\(place.name): no sunrise")
        return
    }
    let middle = rise.addingTimeInterval(set.timeIntervalSince(rise) / 2)
    #expect(abs(middle.timeIntervalSince(noon)) < 3 * 3_600, "\(place.name)")

    let up = try #require(horizonCrossing(near: rise, rising: true, latitude: place.latitude, longitude: place.longitude))
    let down = try #require(horizonCrossing(near: set, rising: false, latitude: place.latitude, longitude: place.longitude))
    #expect(abs(rise.timeIntervalSince(up)) < 60, "\(place.name) sunrise")
    #expect(abs(set.timeIntervalSince(down)) < 60, "\(place.name) sunset")
}

@Test func daylightStaysContinuousAcrossOslosClockChanges() throws {
    // Summer time starts 29 March 2026 and ends 25 October 2026. The day length changes by
    // minutes; the clock time of sunrise jumps by about an hour.
    let (mar28, mar29, mar30) = (try sunTimes(2026, 3, 28), try sunTimes(2026, 3, 29), try sunTimes(2026, 3, 30))
    #expect((240...420).contains(mar29.length - mar28.length))
    #expect((240...420).contains(mar30.length - mar29.length))
    #expect((50...62).contains(mar29.rise - mar28.rise))

    let (oct24, oct25, oct26) = (try sunTimes(2026, 10, 24), try sunTimes(2026, 10, 25), try sunTimes(2026, 10, 26))
    #expect((240...420).contains(oct24.length - oct25.length))
    #expect((240...420).contains(oct25.length - oct26.length))
    #expect((-62...(-50)).contains(oct25.rise - oct24.rise))
}

@Test func at70NorthTheSunStaysUpInJuneAndDownInDecember() {
    let june = Solar.day(containing: at(utc, 2026, 6, 21), latitude: 70, longitude: 0, calendar: utc)
    let december = Solar.day(containing: at(utc, 2026, 12, 21), latitude: 70, longitude: 0, calendar: utc)
    #expect(june == .alwaysUp)
    #expect(december == .alwaysDown)
    #expect(june.length == 86_400)
    #expect(december.length == 0)
}

// MARK: - Night dim

@Test(arguments: [
    // Most of the year the lowest sun is far below -6: dim from -6 to -12.
    (-5.0, -52.0, 0.0), (-9.0, -52.0, 0.5), (-12.0, -52.0, 1.0), (-20.0, -52.0, 1.0),
    // June at 64.15 N: threshold -1.41, full at the day's lowest, -2.41.
    (-1.0, -2.41, 0.0), (-1.91, -2.41, 0.5), (-2.41, -2.41, 1.0),
    // June at 70 N: the sun never sets; dim around its lowest point, +3.44.
    (5.0, 3.44, 0.0), (3.94, 3.44, 0.5), (3.44, 3.44, 1.0),
])
func nightDimFollowsTheSunRatherThanTheClock(elevation: Double, lowest: Double, expected: Double) {
    #expect(abs(Solar.nightDim(elevation: elevation, lowest: lowest) - expected) < 0.001)
}

@Test func reykjavikDimsFullyAtJuneSolarMidnight() {
    let solarMidnight = at(utc, 2026, 6, 22, 1, 30)
    #expect(Solar.nightDim(at: solarMidnight, latitude: reykjavik.latitude, longitude: reykjavik.longitude) > 0.9)
    let solarNoon = at(utc, 2026, 6, 21, 13, 30)
    #expect(Solar.nightDim(at: solarNoon, latitude: reykjavik.latitude, longitude: reykjavik.longitude) == 0)
}
