import Foundation
import NorthlightKit

/// What the Mac reads from one EventKit occurrence, kept apart from EventKit so the
/// mapping to the TV's event can be tested on its own.
public struct MacEvent: Sendable, Equatable {
    public var identifier: String
    /// When this occurrence was first scheduled, which a moved occurrence keeps.
    public var occurrence: Date
    public var title: String?
    public var location: String?
    public var start: Date
    public var end: Date
    public var isAllDay: Bool

    public init(identifier: String, occurrence: Date, title: String?, location: String?,
                start: Date, end: Date, isAllDay: Bool) {
        self.identifier = identifier
        self.occurrence = occurrence
        self.title = title
        self.location = location
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
    }

    /// The event as the TV reads it. An all-day event is a run of dates, not of
    /// instants, so its dates are read on the Mac and rebuilt as midnights in the
    /// place's zone, with an exclusive end as a calendar feed gives it.
    public func calendarEvent(macCalendar: Calendar, placeCalendar: Calendar) -> CalendarEvent {
        let id = "\(identifier)@\(Int(occurrence.timeIntervalSince1970))"
        let title = title.flatMap { $0.isEmpty ? nil : $0 } ?? "Busy"
        let location = location.flatMap { $0.isEmpty ? nil : $0 }
        guard isAllDay else {
            return CalendarEvent(id: id, title: title, location: location, start: start, end: end, isAllDay: false)
        }
        func midnight(_ date: Date) -> Date {
            var components = macCalendar.dateComponents([.year, .month, .day], from: date)
            components.calendar = placeCalendar
            components.timeZone = placeCalendar.timeZone
            return placeCalendar.date(from: components) ?? date
        }
        let first = midnight(start)
        let last = midnight(max(start, end.addingTimeInterval(-1)))
        let end = placeCalendar.date(byAdding: .day, value: 1, to: last) ?? last
        return CalendarEvent(id: id, title: title, location: location, start: first, end: end, isAllDay: true)
    }
}
