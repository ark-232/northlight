import Foundation

/// What the TV asks its Mac to write the day's briefing from (D10): the day's facts as
/// data, with the TV's locale and units, so the Mac writes in the viewer's own units.
public struct BriefingRequest: Codable, Sendable, Equatable {
    public var place: Place
    public var day: Date
    public var locale: String
    public var units: Units?
    public var weather: Weather?
    /// Today's, in the place's zone.
    public var events: [CalendarEvent]
    /// The ones in force when asked.
    public var alerts: [WeatherAlert]

    public init(place: Place, at now: Date, locale: String, units: Units?, weather: Weather?,
                events: [CalendarEvent], alerts: [WeatherAlert]) {
        self.place = place
        self.day = now
        self.locale = locale
        self.units = units
        self.weather = weather
        let today = place.calendar.dateInterval(of: .day, for: now)!
        self.events = events.filter { $0.start < today.end && $0.end > today.start }
        self.alerts = alerts.filter { $0.isActive(at: now) }
    }
}

/// The day's briefing as the Mac wrote it, or why it could not write one.
public enum Briefing: Codable, Sendable, Equatable {
    case written(text: String, at: Date)
    case unavailable(reason: String, at: Date)

    public var at: Date {
        switch self {
        case .written(_, let at), .unavailable(_, let at): at
        }
    }

    /// From five in the morning until an answer of either kind arrives, so a Mac that
    /// wakes late still writes the day's.
    public static func isDue(after last: Date?, at now: Date, calendar: Calendar) -> Bool {
        let five = calendar.date(bySettingHour: 5, minute: 0, second: 0, of: now)!
        return now >= five && (last.map { $0 < five } ?? true)
    }
}
