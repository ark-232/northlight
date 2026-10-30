import Foundation
import Testing
@testable import NorthlightKit

private let now = Date(timeIntervalSince1970: 1_792_000_000)

private func feed(_ value: [Int]?, fetched secondsAgo: TimeInterval? = nil, error: String? = nil,
                  interval: TimeInterval = 300) -> Loaded<[Int]> {
    Loaded(interval: interval, value: value, fetchedAt: secondsAgo.map { now.addingTimeInterval(-$0) }, lastError: error)
}

// MARK: - What a tile may show

@Test func aFeedThatHasNeverAnsweredIsLoading() {
    #expect(feed(nil).state(asOf: now) == .loading)
}

@Test func aFreshValueIsShown() {
    #expect(feed([1, 2], fetched: 10).state(asOf: now) == .ready([1, 2]))
}

@Test func anEmptyAnswerIsAnAnswer() {
    // The empty sentence ("Nothing above M2.5 this week") is honest only here,
    // after a fetch that succeeded.
    #expect(feed([], fetched: 10).state(asOf: now) == .ready([]))
}

@Test func aCachedValueShowsUntilSomethingFails() {
    // At launch the disk seed can be days old; nothing has failed yet.
    #expect(feed([7], fetched: 3 * 86_400).state(asOf: now) == .ready([7]))
}

@Test func aValueOutlivesAFailureForThreeIntervals() {
    let failing = feed([7], fetched: 899, error: "HTTP 503")
    #expect(failing.state(asOf: now) == .ready([7]))
    #expect(failing.lastError == "HTTP 503")
}

@Test func aFailedFeedPastThreeIntervalsIsUnavailable() {
    #expect(feed([7], fetched: 901, error: "HTTP 503").state(asOf: now) == .unavailable("HTTP 503"))
}

@Test func aFailedQuakeFetchReadsAsFailedNotEmpty() {
    var quakes = Loaded<[Quake]>(interval: 300)
    quakes.fail("The request timed out.")
    #expect(quakes.state(asOf: now) == .unavailable("The request timed out."))
}

@Test func successClearsTheFailure() {
    var loaded = feed([1], fetched: 2_000, error: "HTTP 500")
    loaded.succeed([2], at: now)
    #expect(loaded.state(asOf: now) == .ready([2]))
    #expect(loaded.lastError == nil)
    #expect(loaded.age(asOf: now) == 0)
}

@Test func aFailureKeepsTheValueItHad() {
    var loaded = feed([1], fetched: 10)
    loaded.fail("HTTP 503")
    #expect(loaded.state(asOf: now) == .ready([1]))
}

@Test func theCutoffIsThreeOfTheFeedsOwnIntervalsPastItsLastSuccess() {
    #expect(feed([1], fetched: 90, error: "x", interval: 30).state(asOf: now) == .ready([1]))
    #expect(feed([1], fetched: 91, error: "x", interval: 30).state(asOf: now) == .unavailable("x"))
    #expect(feed([1], fetched: 3_599, error: "x", interval: 1_200).state(asOf: now) == .ready([1]))
    #expect(feed([1], fetched: 3_601, error: "x", interval: 1_200).state(asOf: now) == .unavailable("x"))
}

// MARK: - When a tile names its age

/// The screen redraws once a minute, so a fresh value names no age; one more than
/// two intervals old says how old it is.
@Test func onlyAStaleValueNamesItsAge() {
    #expect(feed([1], fetched: 590).staleAge(asOf: now) == nil)
    #expect(feed([1], fetched: 610).staleAge(asOf: now) == 610)
    #expect(feed(nil).staleAge(asOf: now) == nil)
}
