import Foundation
import Testing
@testable import NorthlightKit

private let reykjavik = Place(name: "Reykjavík", latitude: 64.1466, longitude: -21.9426,
                              timeZoneIdentifier: "Atlantic/Reykjavik", countryCode: "IS")

/// 19 Oct 2026 at `hour`:`minute` in Reykjavík, which keeps UTC.
private func at(_ hour: Int, _ minute: Int = 0, day: Int = 19) -> Date {
    reykjavik.calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

private func event(_ title: String, _ start: Date, allDay: Bool = false) -> CalendarEvent {
    CalendarEvent(id: title, title: title, location: nil, start: start, end: start.addingTimeInterval(1_800), isAllDay: allDay)
}

struct BriefingTests {
    @Test func aBriefingIsDueFromFiveInTheMorningUntilOneIsWritten() {
        let calendar = reykjavik.calendar
        #expect(!Briefing.isDue(after: nil, at: at(4, 59), calendar: calendar))
        #expect(Briefing.isDue(after: nil, at: at(5), calendar: calendar))
        #expect(Briefing.isDue(after: at(23, day: 18), at: at(7), calendar: calendar))
        #expect(!Briefing.isDue(after: at(5, 12), at: at(22), calendar: calendar))
        #expect(Briefing.isDue(after: at(5, 12), at: at(5, day: 20), calendar: calendar))
    }

    @Test func theRequestCarriesTodaysEventsAndTheAlertsInForce() {
        let alerts = [WeatherAlert(id: "on", event: "Gale Warning", headline: nil, severity: "Severe", ends: at(18), expires: at(18)),
                      WeatherAlert(id: "off", event: "Frost Advisory", headline: nil, severity: "Minor", ends: at(6), expires: at(6))]
        let events = [event("Standup", at(9, 30)), event("Holiday", at(0), allDay: true), event("Dentist", at(10, day: 20))]
        let request = BriefingRequest(place: reykjavik, at: at(7), locale: "en_IS", units: .metric,
                                      weather: nil, events: events, alerts: alerts)
        #expect(request.events.map(\.title) == ["Standup", "Holiday"])
        #expect(request.alerts.map(\.event) == ["Gale Warning"])
    }

    @Test func briefingFramesCrossInEitherDirection() throws {
        let request = Frame.briefingRequest(BriefingRequest(place: reykjavik, at: at(7), locale: "en_IS", units: nil,
                                                            weather: Samples.weather(at: at(7)), events: [event("Standup", at(9, 30))],
                                                            alerts: []))
        let written = Frame.briefing(.written(text: "Rain until noon, then clearing. Standup at 9:30.", at: at(7, 1)))
        let refused = Frame.briefing(.unavailable(reason: "Apple Intelligence is off on this Mac.", at: at(7, 1)))
        var reader = FrameReader()
        #expect(try reader.read(try [request, written, refused].map { try $0.encoded() }.reduce(Data(), +)) == [request, written, refused])
    }
}

private let losAngeles = Place(name: "Los Angeles", latitude: 34.0522, longitude: -118.2437,
                               timeZoneIdentifier: "America/Los_Angeles", countryCode: "US")

struct BriefingZoneTests {
    /// Five in the morning is the place's, not UTC's: 05:00 in Los Angeles is 12:00 or 13:00 UTC.
    @Test func dueAndTodayFollowThePlacesClock() {
        let calendar = losAngeles.calendar
        func local(_ hour: Int, day: Int = 19) -> Date {
            calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour))!
        }
        #expect(!Briefing.isDue(after: nil, at: local(4), calendar: calendar))
        #expect(Briefing.isDue(after: nil, at: local(5), calendar: calendar))
        let late = CalendarEvent(id: "late", title: "Late", location: nil, start: local(22), end: local(23), isAllDay: false)
        let trip = CalendarEvent(id: "trip", title: "Trip", location: nil, start: local(9, day: 18), end: local(9, day: 21), isAllDay: false)
        let next = CalendarEvent(id: "next", title: "Next", location: nil, start: local(1, day: 20), end: local(2, day: 20), isAllDay: false)
        let request = BriefingRequest(place: losAngeles, at: local(7), locale: "en_US", units: nil, weather: nil,
                                      events: [late, trip, next], alerts: [])
        // Today's events, including one that began before today and runs through it.
        #expect(request.events.map(\.title) == ["Late", "Trip"])
    }
}
