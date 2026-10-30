import Foundation
import Testing
@testable import NorthlightAgent
@testable import NorthlightKit

private func calendar(_ zone: String) -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: zone)!
    return calendar
}

private let tokyo = calendar("Asia/Tokyo")
private let losAngeles = calendar("America/Los_Angeles")

private func date(_ calendar: Calendar, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute, second: second))!
}

@Test func eachOccurrenceOfARepeatingEventHasItsOwnID() {
    let standup = { (day: Int) in
        MacEvent(identifier: "ABC", occurrence: date(tokyo, 10, day, 9), title: "Standup", location: nil,
                 start: date(tokyo, 10, day, 9), end: date(tokyo, 10, day, 9, 15), isAllDay: false)
    }
    let first = standup(20).calendarEvent(macCalendar: tokyo, placeCalendar: losAngeles)
    let second = standup(21).calendarEvent(macCalendar: tokyo, placeCalendar: losAngeles)
    #expect(first.id != second.id)
    #expect(first.id.hasPrefix("ABC"))
}

@Test func aTimedEventKeepsItsInstant() {
    let event = MacEvent(identifier: "A", occurrence: date(tokyo, 10, 20, 9), title: "Call", location: "Room 4",
                         start: date(tokyo, 10, 20, 9), end: date(tokyo, 10, 20, 10), isAllDay: false)
        .calendarEvent(macCalendar: tokyo, placeCalendar: losAngeles)
    #expect(event.start == date(tokyo, 10, 20, 9))
    #expect(event.end == date(tokyo, 10, 20, 10))
    #expect(event.location == "Room 4")
    #expect(!event.isAllDay)
}

@Test func anAllDayEventFallsOnTheSameDatesInThePlacesZone() {
    // EventKit ends a one-day event a second before the next midnight on the Mac.
    let holiday = MacEvent(identifier: "H", occurrence: date(tokyo, 10, 20), title: "Holiday", location: nil,
                           start: date(tokyo, 10, 20), end: date(tokyo, 10, 20, 23, 59, 59), isAllDay: true)
        .calendarEvent(macCalendar: tokyo, placeCalendar: losAngeles)
    #expect(holiday.start == date(losAngeles, 10, 20))
    #expect(holiday.end == date(losAngeles, 10, 21))
    #expect(holiday.isAllDay)
}

@Test func aMultiDayAllDayEventEndingAtMidnightKeepsItsLength() {
    let trip = MacEvent(identifier: "T", occurrence: date(tokyo, 10, 20), title: "Trip", location: nil,
                        start: date(tokyo, 10, 20), end: date(tokyo, 10, 23), isAllDay: true)
        .calendarEvent(macCalendar: tokyo, placeCalendar: losAngeles)
    #expect(trip.start == date(losAngeles, 10, 20))
    #expect(trip.end == date(losAngeles, 10, 23))
}

@Test func anUntitledEventReadsAsBusy() {
    let event = MacEvent(identifier: "U", occurrence: date(tokyo, 10, 20, 9), title: nil, location: "",
                         start: date(tokyo, 10, 20, 9), end: date(tokyo, 10, 20, 10), isAllDay: false)
        .calendarEvent(macCalendar: tokyo, placeCalendar: losAngeles)
    #expect(event.title == "Busy")
    #expect(event.location == nil)
}
