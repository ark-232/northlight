import Foundation
import Testing
@testable import NorthlightKit

private let now = Date(timeIntervalSince1970: 1_760_900_000)
private let hour: TimeInterval = 3_600

struct SpeedScheduleTests {
    /// Gaps are exponential with a twelve-hour mean, so no clock time repeats.
    @Test func gapsAreExponentialWithATwelveHourMeanHeldBetweenTwoAndTwentyFourHours() {
        #expect(SpeedSchedule.next(from: now, history: [], uniform: 0) == now.addingTimeInterval(2 * hour))
        let mean = SpeedSchedule.next(from: now, history: [], uniform: 1 - exp(-1)).timeIntervalSince(now)
        #expect(abs(mean - 12 * hour) < 1)
        #expect(SpeedSchedule.next(from: now, history: [], uniform: 0.99999) == now.addingTimeInterval(24 * hour))
    }

    /// M-Lab allows automated clients four tests a day.
    @Test func aFifthTestWaitsUntilTheOldestOfTheLastFourIsADayOld() {
        let four = [-20.0, -12, -6, -1].map { now.addingTimeInterval($0 * hour) }
        #expect(SpeedSchedule.next(from: now, history: four, uniform: 0) == now.addingTimeInterval(4 * hour))
        let older = [-30.0, -12, -6, -1].map { now.addingTimeInterval($0 * hour) }
        #expect(SpeedSchedule.next(from: now, history: older, uniform: 0) == now.addingTimeInterval(2 * hour))
    }

    /// The day the limit counts is the last 24 hours, manual tests included.
    @Test func theDaysCountIsTheTestsInTheLast24Hours() {
        let history = [-25.0, -23, -1].map { now.addingTimeInterval($0 * hour) }
        #expect(SpeedSchedule.count(in: history, asOf: now) == 2)
        #expect(SpeedSchedule.count(in: [], asOf: now) == 0)
    }
}
