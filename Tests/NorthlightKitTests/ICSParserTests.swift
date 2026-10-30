import Foundation
import Testing
@testable import NorthlightKit

/// The window is fixed rather than relative to "now" so these assertions stay
/// true next month. Sun 18 Oct 2026 → Sun 1 Nov 2026, Los Angeles time.
private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

private var testCalendar: Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = losAngeles
    return cal
}

private func at(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    testCalendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

private var window: DateInterval {
    DateInterval(start: at(2026, 10, 18), end: at(2026, 11, 1))
}

private func loadFixture() throws -> String {
    let url = try #require(Bundle.module.url(forResource: "sample", withExtension: "ics", subdirectory: "Fixtures"))
    return try String(contentsOf: url, encoding: .utf8)
}

private func parsed() throws -> [CalendarEvent] {
    ICSParser.parse(try loadFixture(), window: window, calendar: testCalendar)
}

@Test func parsesTimedEventWithLocation() throws {
    let events = try parsed()
    let brief = try #require(events.first { $0.title == "Morning brief" })
    #expect(brief.start == at(2026, 10, 20, 9, 0))
    #expect(brief.end == at(2026, 10, 20, 10, 0))
    #expect(brief.location == "Room 4B")
    #expect(brief.isAllDay == false)
}

@Test func nestedAlarmDoesNotOverwriteEventSummary() throws {
    let events = try parsed()
    #expect(!events.contains { $0.title.contains("alarm summary") })
}

@Test func parsesAllDayEvent() throws {
    let events = try parsed()
    let training = try #require(events.first { $0.title == "Training day" })
    #expect(training.isAllDay)
    #expect(training.start == at(2026, 10, 21))
    #expect(training.end.timeIntervalSince(training.start) == 86_400)
}

@Test func weeklyByDayExpandsToListedWeekdays() throws {
    let standups = try parsed().filter { $0.title == "Standup" }.map(\.start).sorted()
    // Mon 19, Wed 21, Mon 26, Wed 28 — all inside the window.
    #expect(standups == [
        at(2026, 10, 19, 14, 0),
        at(2026, 10, 21, 14, 0),
        at(2026, 10, 26, 14, 0),
        at(2026, 10, 28, 14, 0),
    ])
}

@Test func exdateRemovesExactlyOneInstance() throws {
    let checks = try parsed().filter { $0.title == "Daily check" }.map(\.start).sorted()
    // COUNT=5 from Oct 19 would be 19–23; Oct 21 is excluded by EXDATE.
    #expect(checks == [
        at(2026, 10, 19, 8, 0),
        at(2026, 10, 20, 8, 0),
        at(2026, 10, 22, 8, 0),
        at(2026, 10, 23, 8, 0),
    ])
}

@Test func countIsHonoured() throws {
    let checks = try parsed().filter { $0.title == "Daily check" }
    #expect(checks.count == 4)
    #expect(checks.allSatisfy { $0.start <= at(2026, 10, 23, 8, 0) })
}

@Test func recurrenceIDOverridesThatInstanceOnly() throws {
    let events = try parsed()
    let lunches = events.filter { $0.title.hasPrefix("Lunch") }.sorted { $0.start < $1.start }

    #expect(lunches.count == 3)
    // The Oct 20 noon instance is replaced by the 16:30 override.
    #expect(!lunches.contains { $0.title == "Lunch" && $0.start == at(2026, 10, 20, 12, 0) })

    let moved = try #require(lunches.first { $0.title == "Lunch (moved)" })
    #expect(moved.start == at(2026, 10, 20, 16, 30))

    #expect(lunches.contains { $0.title == "Lunch" && $0.start == at(2026, 10, 19, 12, 0) })
    #expect(lunches.contains { $0.title == "Lunch" && $0.start == at(2026, 10, 21, 12, 0) })
}

@Test func foldedLineIsRejoinedAndUnescaped() throws {
    let events = try parsed()
    let folded = try #require(events.first { $0.title.hasPrefix("A very long title") })
    #expect(folded.title == "A very long title that Google folds across lines because it exceeds seventy-five octets, with a comma")
}

@Test func monthlyNthWeekdayLandsOnThirdTuesday() throws {
    let meetings = try parsed().filter { $0.title == "Design review" }.map(\.start)
    // Third Tuesday of October 2026 is the 20th.
    #expect(meetings == [at(2026, 10, 20, 10, 0)])
}

@Test func eventsAreSortedByStart() throws {
    let starts = try parsed().map(\.start)
    #expect(starts == starts.sorted())
}

@Test func durationFallbackIsUsedWhenDTENDMissing() throws {
    let ics = """
    BEGIN:VCALENDAR
    BEGIN:VEVENT
    UID:dur@test
    DTSTART;TZID=America/Los_Angeles:20261020T080000
    DURATION:PT1H30M
    SUMMARY:Ninety minutes
    END:VEVENT
    END:VCALENDAR
    """
    let events = ICSParser.parse(ics, window: window, calendar: testCalendar)
    let e = try #require(events.first)
    #expect(e.end.timeIntervalSince(e.start) == 5_400)
}

@Test func utcTimestampsConvertToTheSameInstant() throws {
    let ics = """
    BEGIN:VCALENDAR
    BEGIN:VEVENT
    UID:utc@test
    DTSTART:20261020T160000Z
    DTEND:20261020T170000Z
    SUMMARY:UTC event
    END:VEVENT
    END:VCALENDAR
    """
    let events = ICSParser.parse(ics, window: window, calendar: testCalendar)
    let e = try #require(events.first)
    // Los Angeles is UTC-7 on 20 Oct 2026 (still daylight time), so 16:00Z is 09:00 local.
    #expect(e.start == at(2026, 10, 20, 9, 0))
}

@Test func quotedTZIDParameterWithColonsDoesNotBreakParsing() throws {
    let line = try #require(ContentLine("DTSTART;TZID=\"America/Los_Angeles\";VALUE=DATE-TIME:20261020T090000"))
    #expect(line.name == "DTSTART")
    #expect(line.params["TZID"] == "America/Los_Angeles")
    #expect(line.value == "20261020T090000")
}

@Test func malformedFeedYieldsNothingRatherThanCrashing() {
    #expect(ICSParser.parse("", window: window, calendar: testCalendar).isEmpty)
    #expect(ICSParser.parse("BEGIN:VEVENT\nEND:VEVENT", window: window, calendar: testCalendar).isEmpty)
    #expect(ICSParser.parse("garbage\nmore garbage", window: window, calendar: testCalendar).isEmpty)
}

@Test func isoDurationParsesWeeksAndDays() {
    #expect(RawEvent.parseDuration("P1W") == 604_800)
    #expect(RawEvent.parseDuration("P2D") == 172_800)
    #expect(RawEvent.parseDuration("PT45M") == 2_700)
    #expect(RawEvent.parseDuration("nonsense") == nil)
}
