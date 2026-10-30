import Foundation
import Testing
@testable import NorthlightKit

// Shapes from RFC 4791 and RFC 5397 as iCloud answers them: DAV: as the default namespace,
// the principal relative to caldav.icloud.com, the calendar home on a partition host.

private let principal = """
<?xml version="1.0" encoding="UTF-8"?>
<multistatus xmlns="DAV:"><response><href>/</href><propstat><prop>
<current-user-principal><href>/1234567890/principal/</href></current-user-principal>
</prop><status>HTTP/1.1 200 OK</status></propstat></response></multistatus>
"""

private let home = """
<?xml version="1.0" encoding="UTF-8"?>
<multistatus xmlns="DAV:"><response><href>/1234567890/principal/</href><propstat><prop>
<calendar-home-set xmlns="urn:ietf:params:xml:ns:caldav"><href xmlns="DAV:">https://p42-caldav.icloud.com:443/1234567890/calendars/</href></calendar-home-set>
</prop><status>HTTP/1.1 200 OK</status></propstat></response></multistatus>
"""

/// The home itself, two event calendars, a reminders list, and the scheduling inbox.
private let collections = """
<?xml version="1.0" encoding="UTF-8"?>
<d:multistatus xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
 <d:response><d:href>/1234567890/calendars/</d:href><d:propstat><d:prop><d:displayname>Calendars</d:displayname>
  <d:resourcetype><d:collection/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
 <d:response><d:href>/1234567890/calendars/home/</d:href><d:propstat><d:prop><d:displayname>Home</d:displayname>
  <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
  <c:supported-calendar-component-set><c:comp name="VEVENT"/></c:supported-calendar-component-set></d:prop>
  <d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
 <d:response><d:href>/1234567890/calendars/work%20shifts/</d:href><d:propstat><d:prop><d:displayname>Work &amp; shifts</d:displayname>
  <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
  <c:supported-calendar-component-set><c:comp name="VEVENT"/><c:comp name="VTODO"/></c:supported-calendar-component-set></d:prop>
  <d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
 <d:response><d:href>/1234567890/calendars/tasks/</d:href><d:propstat><d:prop><d:displayname>Reminders</d:displayname>
  <d:resourcetype><d:collection/><c:calendar/></d:resourcetype>
  <c:supported-calendar-component-set><c:comp name="VTODO"/></c:supported-calendar-component-set></d:prop>
  <d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
 <d:response><d:href>/1234567890/calendars/inbox/</d:href><d:propstat><d:prop><d:displayname>Inbox</d:displayname>
  <d:resourcetype><d:collection/><c:schedule-inbox/></d:resourcetype></d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat></d:response>
</d:multistatus>
"""

/// One weekly event, as the master with its rule, for the parser to expand.
private let report = """
<?xml version="1.0" encoding="UTF-8"?>
<multistatus xmlns="DAV:"><response><href>/1234567890/calendars/home/standup.ics</href><propstat><prop>
<getetag>"c0ffee"</getetag>
<calendar-data xmlns="urn:ietf:params:xml:ns:caldav">BEGIN:VCALENDAR
VERSION:2.0
PRODID:-//Apple Inc.//iCloud//EN
BEGIN:VEVENT
UID:standup-1
DTSTART:20261019T170000Z
DTEND:20261019T171500Z
RRULE:FREQ=WEEKLY;COUNT=3
SUMMARY:Standup
END:VEVENT
END:VCALENDAR
</calendar-data></prop><status>HTTP/1.1 200 OK</status></propstat></response></multistatus>
"""

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}

private func utcDate(_ day: Int, _ hour: Int = 0) -> Date {
    utc.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
}

struct CalDAVTests {
    @Test func thePrincipalComesFromTheServerRoot() throws {
        #expect(try CalDAV.principal(from: Data(principal.utf8), at: CalDAV.iCloud)
                == URL(string: "https://caldav.icloud.com/1234567890/principal/"))
    }

    @Test func theCalendarHomeIsOnTheAccountsPartition() throws {
        #expect(try CalDAV.home(from: Data(home.utf8), at: URL(string: "https://caldav.icloud.com/1234567890/principal/")!)
                == URL(string: "https://p42-caldav.icloud.com:443/1234567890/calendars/"))
    }

    @Test func onlyCalendarsThatHoldEventsAreListed() throws {
        let at = URL(string: "https://p42-caldav.icloud.com:443/1234567890/calendars/")!
        #expect(try CalDAV.calendars(from: Data(collections.utf8), at: at) == [
            CalDAV.Calendar(url: URL(string: "https://p42-caldav.icloud.com:443/1234567890/calendars/home/")!, name: "Home"),
            CalDAV.Calendar(url: URL(string: "https://p42-caldav.icloud.com:443/1234567890/calendars/work%20shifts/")!,
                            name: "Work & shifts"),
        ])
    }

    @Test func aReportsCalendarDataExpandsThroughTheICSParser() throws {
        let texts = try CalDAV.calendarData(from: Data(report.utf8))
        #expect(texts.count == 1)
        let window = DateInterval(start: utcDate(18), end: utcDate(31))
        let events = texts.flatMap { ICSParser.parse($0, window: window, calendar: utc) }
        #expect(events.map(\.start) == [utcDate(19, 17), utcDate(26, 17)])
        #expect(events.allSatisfy { $0.title == "Standup" })
    }

    @Test func theEventQueryNamesTheWindowInUTC() {
        let query = CalDAV.eventQuery(over: DateInterval(start: utcDate(18, 9), end: utcDate(31)))
        #expect(query.contains(#"<c:time-range start="20261018T090000Z" end="20261031T000000Z"/>"#))
    }

    /// A shape this reader does not know fails loudly, rather than reading as no calendars.
    @Test func aMultistatusWithoutWhatWasAskedForThrows() {
        #expect(throws: FeedError.self) { try CalDAV.principal(from: Data(home.utf8), at: CalDAV.iCloud) }
        #expect(throws: FeedError.self) { try CalDAV.home(from: Data("not xml".utf8), at: CalDAV.iCloud) }
    }
}

/// Answers every request with the next canned response and keeps what was asked.
final class CannedCalDAV: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var answers: [(status: Int, body: String)] = []
    nonisolated(unsafe) static var asked: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.asked.append(request)
        let answer = Self.answers.removeFirst()
        let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func http() -> HTTP {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CannedCalDAV.self]
        return HTTP(userAgent: "test", configuration: configuration)
    }
}

@Suite(.serialized)
struct CalDAVBoundaryTests {
    /// The account's password goes to iCloud and nowhere else, whatever an answer names.
    @Test func anAnswerNamingAHostOffICloudIsRefused() {
        let elsewhere = home.replacingOccurrences(of: "https://p42-caldav.icloud.com:443", with: "https://evil.example")
        #expect(throws: FeedError.self) { try CalDAV.home(from: Data(elsewhere.utf8), at: CalDAV.iCloud) }
        let plain = home.replacingOccurrences(of: "https://", with: "http://")
        #expect(throws: FeedError.self) { try CalDAV.home(from: Data(plain.utf8), at: CalDAV.iCloud) }
    }

    @Test func anAnswerThatIsNotASuccessFailsRatherThanReadingAsEmpty() {
        let full = report.replacingOccurrences(of: "HTTP/1.1 200 OK", with: "HTTP/1.1 507 Insufficient Storage")
        #expect(throws: FeedError.self) { try CalDAV.calendarData(from: Data(full.utf8)) }
        let unfamiliar = collections.replacingOccurrences(of: "HTTP/1.1 200 OK", with: "HTTP/1.1 404 Not Found")
        #expect(throws: FeedError.self) { try CalDAV.calendars(from: Data(unfamiliar.utf8), at: CalDAV.iCloud) }
    }

    @Test func discoveryAuthenticatesEachStepAndARefusedPasswordSaysReconnect() async throws {
        CannedCalDAV.answers = [(207, principal), (207, home), (207, collections)]
        CannedCalDAV.asked = []
        let found = try await CannedCalDAV.http().icloudCalendars(appleID: "someone@icloud.com", password: "abcd-efgh")
        #expect(found.count == 2)
        let basic = "Basic " + Data("someone@icloud.com:abcd-efgh".utf8).base64EncodedString()
        #expect(CannedCalDAV.asked.map { $0.value(forHTTPHeaderField: "Authorization") } == [basic, basic, basic])
        #expect(CannedCalDAV.asked.map { $0.value(forHTTPHeaderField: "Depth") } == ["0", "0", "1"])
        #expect(CannedCalDAV.asked.map(\.httpMethod) == ["PROPFIND", "PROPFIND", "PROPFIND"])

        CannedCalDAV.answers = [(401, "")]
        await #expect(throws: FeedError.refused("iCloud refused the password. Reconnect iCloud in Settings.")) {
            _ = try await CannedCalDAV.http().icloudCalendars(appleID: "someone@icloud.com", password: "wrong")
        }
    }

    @Test func aStoredCalendarOffICloudIsNeverAsked() async {
        CannedCalDAV.answers = []
        CannedCalDAV.asked = []
        let account = ICloudAccount(appleID: "someone@icloud.com", password: "abcd-efgh",
                                    calendars: [CalDAV.Calendar(url: URL(string: "https://127.0.0.1:18081/cal/")!, name: "Away")])
        await #expect(throws: FeedError.self) {
            _ = try await CannedCalDAV.http().icloudEvents(account, window: DateInterval(start: .now, duration: 86_400), calendar: .current)
        }
        #expect(CannedCalDAV.asked.isEmpty)
    }
}
