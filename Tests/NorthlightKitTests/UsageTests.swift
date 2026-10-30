import Foundation
import Testing
@testable import NorthlightKit

private let observed = Date(timeIntervalSince1970: 1_760_890_000)

struct UsageTests {
    @Test func theWrappersFileDecodes() throws {
        let file = #"{"five_hour":{"used_percentage":42.5,"resets_at":1760900000},"seven_day":{"used_percentage":18,"resets_at":1761200000},"observed_at":1760890000}"#
        let reading = try JSONDecoder().decode(UsageReading.self, from: Data(file.utf8))
        #expect(reading == UsageReading(
            fiveHour: .init(usedPercentage: 42.5, resetsAt: Date(timeIntervalSince1970: 1_760_900_000)),
            sevenDay: .init(usedPercentage: 18, resetsAt: Date(timeIntervalSince1970: 1_761_200_000)),
            observedAt: observed))
    }

    @Test func aMissingWindowDecodesAsNone() throws {
        let file = #"{"seven_day":{"used_percentage":3,"resets_at":1761200000},"observed_at":1760890000}"#
        let reading = try JSONDecoder().decode(UsageReading.self, from: Data(file.utf8))
        #expect(reading.fiveHour == nil)
        #expect(reading.sevenDay?.usedPercentage == 3)
    }

    /// Past its reset the window has started again, so the old figure is wrong.
    @Test func aWindowPastItsResetIsHidden() {
        let reading = UsageReading(fiveHour: .init(usedPercentage: 90, resetsAt: observed.addingTimeInterval(600)),
                                   sevenDay: .init(usedPercentage: 18, resetsAt: observed.addingTimeInterval(86_400)),
                                   observedAt: observed)
        let later = reading.current(asOf: observed.addingTimeInterval(601))
        #expect(later.fiveHour == nil)
        #expect(later.sevenDay?.usedPercentage == 18)
        #expect(!later.isEmpty)
        #expect(reading.current(asOf: observed.addingTimeInterval(90_000)).isEmpty)
    }

    /// Claude Code reports usage as of its last reply; a quiet Mac's figure goes stale.
    @Test func freshWhileAnAgentRunsOrForFifteenMinutes() {
        let reading = UsageReading(fiveHour: nil, sevenDay: nil, observedAt: observed)
        #expect(reading.isFresh(asOf: observed.addingTimeInterval(14 * 60), agentRunning: false))
        #expect(!reading.isFresh(asOf: observed.addingTimeInterval(15 * 60), agentRunning: false))
        #expect(reading.isFresh(asOf: observed.addingTimeInterval(3 * 3_600), agentRunning: true))
    }

    @Test func levelsBreakAtSeventyAndNinety() {
        #expect(UsageReading.Level(69.9) == .normal)
        #expect(UsageReading.Level(70) == .warning)
        #expect(UsageReading.Level(89.9) == .warning)
        #expect(UsageReading.Level(90) == .critical)
    }

    @Test func aUsageFrameCrossesTheBridge() throws {
        let frame = Frame.usage(UsageReading(fiveHour: .init(usedPercentage: 42, resetsAt: observed.addingTimeInterval(3_600)),
                                             sevenDay: nil, observedAt: observed))
        var reader = FrameReader()
        #expect(try reader.read(frame.encoded()) == [frame])
    }
}

struct UsageTextTests {
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!
    private let english = Locale(identifier: "en_US")
    /// Monday 19 Oct 2026, 5:10 PM in Los Angeles.
    private let now = Date(timeIntervalSince1970: 1_792_455_000)

    @Test func aResetWithinADayIsATime() {
        let window = UsageReading.Window(usedPercentage: 42.4, resetsAt: now.addingTimeInterval(3 * 3_600))
        #expect(window.line("5 h", now: now, timeZone: losAngeles, locale: english) == "5 h 42 % · resets 8:10\u{202F}PM")
    }

    @Test func aLaterResetIsAWeekday() {
        let window = UsageReading.Window(usedPercentage: 17.6, resetsAt: now.addingTimeInterval(3 * 86_400))
        #expect(window.line("7 d", now: now, timeZone: losAngeles, locale: english) == "7 d 18 % · resets Thu")
    }
}
