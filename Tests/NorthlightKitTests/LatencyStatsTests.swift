import Foundation
import Testing
@testable import NorthlightKit

private let start = Date(timeIntervalSince1970: 1_760_900_000)

/// Probes 30 s apart from `start`, nil for one that got no answer.
private func samples(_ values: [Double?]) -> [LatencySample] {
    values.enumerated().map { LatencySample(date: start.addingTimeInterval(Double($0.offset) * 30), milliseconds: $0.element) }
}

struct LatencyStatsTests {
    @Test func theMedianJitterAndFailuresComeFromTheAnswersAndTheSilences() {
        let stats = LatencyStats(samples([10, 14, 10, nil, 14]))
        #expect(stats.median == 12)
        // Each answer differs from the one before by 4, the failure skipped.
        #expect(stats.jitter == 4)
        #expect(stats.failed == 1)
        #expect(stats.since == start)
    }

    @Test func anOddCountTakesTheMiddleAnswer() {
        #expect(LatencyStats(samples([40, 9, 38])).median == 38)
    }

    @Test func noAnswersHaveNoMedianOrJitter() {
        let stats = LatencyStats(samples([nil, nil]))
        #expect(stats.median == nil)
        #expect(stats.jitter == nil)
        #expect(stats.failed == 2)
        #expect(LatencyStats([]).since == nil)
    }

    @Test func theRingKeepsSixHoursOfProbes() {
        var history = LatencyHistory()
        for sample in samples(Array(repeating: 20, count: 721)) {
            history.record(sample, to: .internet)
        }
        #expect(history.internet.count == 720)
        #expect(history.internet.first?.date == start.addingTimeInterval(30))
    }

    /// A gateway that filters its ports never answers; after five silent probes its hop hides.
    @Test func aGatewayHidesAfterFiveSilentProbes() {
        var history = LatencyHistory()
        for sample in samples([nil, nil, nil, nil]) { history.record(sample, to: .gateway) }
        #expect(!history.gatewayHidden)
        history.record(LatencySample(date: start.addingTimeInterval(120), milliseconds: nil), to: .gateway)
        #expect(history.gatewayHidden)

        var answered = LatencyHistory()
        for sample in samples([2, nil, nil, nil, nil, nil]) { answered.record(sample, to: .gateway) }
        #expect(!answered.gatewayHidden)
        answered.clearGateway()
        #expect(answered.gateway.isEmpty)
    }

    /// The line breaks at a failure and wherever nothing ran for more than three probes.
    @Test func theLineBreaksAtFailuresAndGaps() {
        let probes = samples([20, 21, 22, nil, 23, 24]) + [LatencySample(date: start.addingTimeInterval(330), milliseconds: 25)]
        let runs = LatencyHistory.runs(probes)
        #expect(runs.map { $0.map(\.milliseconds) } == [[20, 21, 22], [23, 24], [25]])
    }

    @Test func theInternetIsGradedOnItsOwnThresholdsAndTheLANOnTighterOnes() {
        #expect(LatencyGrade(milliseconds: 29.9, onLAN: false) == .good)
        #expect(LatencyGrade(milliseconds: 30, onLAN: false) == .fair)
        #expect(LatencyGrade(milliseconds: 99.9, onLAN: false) == .fair)
        #expect(LatencyGrade(milliseconds: 100, onLAN: false) == .poor)
        #expect(LatencyGrade(milliseconds: 4.9, onLAN: true) == .good)
        #expect(LatencyGrade(milliseconds: 5, onLAN: true) == .fair)
        #expect(LatencyGrade(milliseconds: 20, onLAN: true) == .poor)
    }
}
