import Foundation
import Testing
@testable import NorthlightKit

struct HeaderStatusTests {
    @Test func theThreeMostUrgentShowInPriorityOrder() {
        let items = HeaderStatus.items(alerts: ["Wind Advisory", "Flood Watch"], liveElsewhere: .aurora,
                                       agentsRunning: 2, networkFault: true, staleAge: 7_200)
        #expect(items == [.alert("Wind Advisory", more: 1), .liveElsewhere, .agents(2)])
    }

    @Test func aQuietDayShowsNothing() {
        #expect(HeaderStatus.items(alerts: [], liveElsewhere: nil, agentsRunning: 0, networkFault: false, staleAge: nil) == [])
    }

    /// The live line already names a running agent on another page; a count beside it repeats it.
    @Test func agentsLiveElsewhereAreNotCountedTwice() {
        let items = HeaderStatus.items(alerts: [], liveElsewhere: .agents, agentsRunning: 1, networkFault: false, staleAge: 900)
        #expect(items == [.liveElsewhere, .stale(900)])
    }

    @Test func aFaultAndAStaleFeedShowWhenNothingOutranksThem() {
        let items = HeaderStatus.items(alerts: [], liveElsewhere: nil, agentsRunning: 0, networkFault: true, staleAge: 900)
        #expect(items == [.networkFault, .stale(900)])
    }
}

struct HeaderUsageTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func reading(observed ago: TimeInterval, resetsIn: TimeInterval = 3_600) -> UsageReading {
        UsageReading(fiveHour: .init(usedPercentage: 42.4, resetsAt: now.addingTimeInterval(resetsIn)),
                     sevenDay: nil, observedAt: now.addingTimeInterval(-ago))
    }

    private func items(_ usage: UsageReading?, agents: Int = 0) -> [HeaderStatus] {
        HeaderStatus.items(alerts: [], liveElsewhere: nil, agentsRunning: agents, networkFault: false, staleAge: nil,
                           usage: usage, now: now)
    }

    @Test func freshUsageShowsTheFiveHourPercent() {
        #expect(items(reading(observed: 60)) == [.usage(42.4)])
    }

    @Test func usageSitsBelowAgentsAndAboveAFault() {
        let items = HeaderStatus.items(alerts: [], liveElsewhere: nil, agentsRunning: 2, networkFault: true, staleAge: 900,
                                       usage: reading(observed: 60), now: now)
        #expect(items == [.agents(2), .usage(42.4), .networkFault])
    }

    /// An old figure on every page would read as live.
    @Test func staleUsageIsHiddenUnlessAnAgentRuns() {
        #expect(items(reading(observed: 20 * 60)) == [])
        #expect(items(reading(observed: 20 * 60), agents: 1) == [.agents(1), .usage(42.4)])
    }

    @Test func aWindowPastItsResetIsHidden() {
        #expect(items(reading(observed: 60, resetsIn: -1)) == [])
        #expect(items(nil) == [])
    }
}
