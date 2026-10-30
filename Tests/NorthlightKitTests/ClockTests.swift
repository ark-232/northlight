import Foundation
import Testing
@testable import NorthlightKit

/// These must pass under any machine zone: `TZ=Asia/Tokyo swift test`.

private let losAngeles = Place(name: "Los Angeles", latitude: 34.0522, longitude: -118.2437,
                               timeZoneIdentifier: "America/Los_Angeles", countryCode: "US")

private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
}

private func events(_ body: String) -> [CalendarEvent] {
    let ics = "BEGIN:VCALENDAR\r\nBEGIN:VEVENT\r\nUID:x\r\nSUMMARY:Thing\r\n\(body)\r\nEND:VEVENT\r\nEND:VCALENDAR\r\n"
    let window = DateInterval(start: utc(2026, 10, 18, 0), end: utc(2026, 11, 1, 0))
    return ICSParser.parse(ics, window: window, calendar: losAngeles.calendar)
}

@Test func thePlaceCalendarKeepsThePlacesZone() {
    #expect(losAngeles.calendar.timeZone.identifier == "America/Los_Angeles")
    #expect(losAngeles.calendar.startOfDay(for: utc(2026, 10, 19, 12)) == utc(2026, 10, 19, 7))
}

@Test func floatingTimesReadInThePlacesZone() throws {
    let event = try #require(events("DTSTART:20261019T090000\r\nDTEND:20261019T100000").first)
    #expect(event.start == utc(2026, 10, 19, 16))
}

@Test func allDayEventsStartAtThePlacesMidnight() throws {
    let event = try #require(events("DTSTART;VALUE=DATE:20261021\r\nDTEND;VALUE=DATE:20261022").first)
    #expect(event.isAllDay)
    #expect(event.start == utc(2026, 10, 21, 7))
}
