import Foundation
import Testing
@testable import NorthlightKit

@Test func webcalLinksBecomeHTTPS() {
    #expect(calendarFeedURL(from: "webcal://p01-caldav.icloud.com/published/2/abc")
            == URL(string: "https://p01-caldav.icloud.com/published/2/abc"))
}

@Test func pastedAddressesAreTrimmed() {
    #expect(calendarFeedURL(from: "  https://calendar.google.com/calendar/ical/x/private-y/basic.ics\n")
            == URL(string: "https://calendar.google.com/calendar/ical/x/private-y/basic.ics"))
}

@Test func textThatIsNotAWebAddressIsRejected() {
    #expect(calendarFeedURL(from: "my calendar") == nil)
    #expect(calendarFeedURL(from: "ftp://example.com/a.ics") == nil)
    #expect(calendarFeedURL(from: "https://") == nil)
}

struct CalendarMergeTests {
    /// One calendar added both by its .ics address and through iCloud shows once.
    @Test func sourcesMergeByStartWithEachOccurrenceOnce() {
        func event(_ id: String, _ start: Double) -> CalendarEvent {
            CalendarEvent(id: id, title: id, location: nil, start: Date(timeIntervalSince1970: start),
                          end: Date(timeIntervalSince1970: start + 1_800), isAllDay: false)
        }
        let ics = [event("standup@1", 100), event("dentist@1", 300)]
        let icloud = [event("standup@1", 100), event("lunch@1", 200)]
        #expect(CalendarEvent.merged([ics, icloud]).map(\.id) == ["standup@1", "lunch@1", "dentist@1"])
    }
}
