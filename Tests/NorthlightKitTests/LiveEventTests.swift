import Foundation
import Testing
@testable import NorthlightKit

private let reykjavik = Place(name: "Reykjavík", latitude: 64.1466, longitude: -21.9426,
                              timeZoneIdentifier: "Atlantic/Reykjavik", countryCode: "IS")
private let now = Date(timeIntervalSince1970: 1_760_900_000)

/// A quake `kilometres` due north of Reykjavík, `minutes` ago.
private func quake(_ magnitude: Double, kilometres: Double, minutes: Double) -> Quake {
    Quake(id: "\(magnitude) \(kilometres) \(minutes)", magnitude: magnitude, place: "Somewhere",
          time: now.addingTimeInterval(-minutes * 60), depthKm: 10,
          latitude: reykjavik.latitude + kilometres / (6_371.0088 * .pi / 180), longitude: reykjavik.longitude)
}

/// An event starting `minutes` from now and lasting `length` minutes.
private func event(_ title: String, in minutes: Double, for length: Double = 30, allDay: Bool = false) -> CalendarEvent {
    let start = now.addingTimeInterval(minutes * 60)
    return CalendarEvent(id: title, title: title, location: nil, start: start,
                         end: start.addingTimeInterval(length * 60), isAllDay: allDay)
}

private func flight(_ label: String, nm: Double, squawk: String?) -> Flight {
    Flight(id: label, label: label, type: nil, altitudeFeet: 9_000, onGround: false, groundSpeedKnots: 250,
           distanceNM: nm, track: nil, latitude: nil, longitude: nil, squawk: squawk)
}

struct LiveEventTests {
    @Test func aQuakeOfM4WithinThreeHundredKilometresInTheHourIsLive() {
        #expect(LiveEvent.quakes([quake(4.0, kilometres: 299, minutes: 30)], around: reykjavik, at: now) != nil)
        #expect(LiveEvent.quakes([quake(4.0, kilometres: 301, minutes: 30)], around: reykjavik, at: now) == nil)
        #expect(LiveEvent.quakes([quake(3.9, kilometres: 10, minutes: 30)], around: reykjavik, at: now) == nil)
        #expect(LiveEvent.quakes([quake(4.5, kilometres: 10, minutes: 61)], around: reykjavik, at: now) == nil)
    }

    @Test func theLargestLiveQuakeWinsWithItsDistance() {
        let small = quake(4.1, kilometres: 50, minutes: 5), large = quake(4.8, kilometres: 250, minutes: 40)
        guard case .quake(let shown, let distance) = LiveEvent.quakes([small, large], around: reykjavik, at: now) else {
            Issue.record("no live quake")
            return
        }
        #expect(shown == large)
        #expect(abs(distance.converted(to: .kilometers).value - 250) < 0.01)
    }

    @Test func auroraNeedsThirtyPercentUnderADarkClearSky() {
        let likely = Aurora(kp: 5, kpObserved: nil, localProbability: 30, forecastTime: nil)
        #expect(LiveEvent.aurora(likely, sunElevation: -12.1, cloudCover: 49) == .aurora(probability: 30))
        #expect(LiveEvent.aurora(likely, sunElevation: -11.9, cloudCover: 49) == nil)
        #expect(LiveEvent.aurora(likely, sunElevation: -12.1, cloudCover: 50) == nil)
        // An unknown sky is not a clear one.
        #expect(LiveEvent.aurora(likely, sunElevation: -12.1, cloudCover: nil) == nil)
        let unlikely = Aurora(kp: 5, kpObserved: nil, localProbability: 29, forecastTime: nil)
        #expect(LiveEvent.aurora(unlikely, sunElevation: -20, cloudCover: 0) == nil)
    }

    @Test func anEventIsLiveFromTenMinutesBeforeItsStartToItsEnd() {
        #expect(LiveEvent.agenda([event("Standup", in: 10)], at: now) == .event(event("Standup", in: 10)))
        #expect(LiveEvent.agenda([event("Standup", in: 11)], at: now) == nil)
        #expect(LiveEvent.agenda([event("Review", in: -20)], at: now) != nil)
        #expect(LiveEvent.agenda([event("Review", in: -30)], at: now) == nil)
    }

    @Test func theNextEventBeatsOneUnderWayAndAllDayEventsNeverGoLive() {
        let underWay = event("Workshop", in: -45, for: 120), next = event("Call", in: 5)
        #expect(LiveEvent.agenda([underWay, next], at: now) == .event(next))
        #expect(LiveEvent.agenda([event("Holiday", in: -60, for: 1_440, allDay: true)], at: now) == nil)
    }

    @Test func anEmergencySquawkIsLiveAndTheNearestWins() {
        let far = flight("ICE123", nm: 30, squawk: "7700"), near = flight("N123AB", nm: 6, squawk: "7600")
        #expect(LiveEvent.flights([flight("ASA1", nm: 2, squawk: "1200"), far, near]) == .squawk(near))
        #expect(LiveEvent.flights([flight("ASA1", nm: 2, squawk: "1200"), flight("ASA2", nm: 3, squawk: nil)]) == nil)
        #expect(LiveEvent.flights([flight("HJ1", nm: 40, squawk: "7500")]) != nil)
    }

    @Test func aRunningTurnIsLiveAndOneWaitingOnYouWins() {
        let working = AgentStatus(session: "a", agent: "Claude Code", activity: .tool, verb: "Editing Live.swift")
        let waiting = AgentStatus(session: "b", agent: "Claude Code", activity: .waiting, verb: "Waiting for you")
        let idle = AgentStatus(session: "c", agent: "Claude Code", activity: .idle, verb: "Idle")
        #expect(LiveEvent.agents([idle, working]) == .agent(working))
        #expect(LiveEvent.agents([working, waiting]) == .agent(waiting))
        #expect(LiveEvent.agents([idle]) == nil)
    }
}
