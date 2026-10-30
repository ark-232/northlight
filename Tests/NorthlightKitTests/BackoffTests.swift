import Foundation
import Testing
@testable import NorthlightKit

@Test(arguments: zip([0, 1, 2, 3, 4, 5, 6, 20], [30.0, 30, 60, 120, 240, 480, 900, 900]))
func failingFlightsBackOffToFifteenMinutes(failures: Int, expected: TimeInterval) {
    #expect(DashboardStore.delay(afterFailures: failures, interval: 30) == expected)
}

@Test(arguments: zip([0, 1, 2, 6, 7, 20], [1_200.0, 30, 60, 960, 1_200, 1_200]))
func aFailingSlowFeedRetriesSoonThenBacksOffToItsInterval(failures: Int, expected: TimeInterval) {
    #expect(DashboardStore.delay(afterFailures: failures, interval: 1_200) == expected)
}

@Test func aFailingDailyFeedBacksOffToADay() {
    #expect(DashboardStore.delay(afterFailures: 1, interval: 86_400) == 30)
    #expect(DashboardStore.delay(afterFailures: 30, interval: 86_400) == 86_400)
}
