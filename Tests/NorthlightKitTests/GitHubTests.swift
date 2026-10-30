import Foundation
import Testing
@testable import NorthlightKit

private let losAngeles: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
    return calendar
}()

private func day(_ date: String, _ count: Int) -> String {
    let level = [0: "NONE", 1: "FIRST_QUARTILE", 2: "FIRST_QUARTILE", 3: "SECOND_QUARTILE", 4: "THIRD_QUARTILE", 5: "FOURTH_QUARTILE", 6: "FOURTH_QUARTILE"][count]!
    return #"{"date":"\#(date)","contributionCount":\#(count),"contributionLevel":"\#(level)"}"#
}

private let summary = Data("""
{"data":{"viewer":{"id":"U_1","login":"octo","contributionsCollection":{"contributionCalendar":{"weeks":[
  {"contributionDays":[\(day("2026-09-27", 0)),\(day("2026-09-28", 3)),\(day("2026-09-29", 1)),\(day("2026-09-30", 0)),\(day("2026-10-01", 2)),\(day("2026-10-02", 0)),\(day("2026-10-03", 0))]},
  {"contributionDays":[\(day("2026-10-04", 0)),\(day("2026-10-05", 4)),\(day("2026-10-06", 0)),\(day("2026-10-07", 1)),\(day("2026-10-08", 0)),\(day("2026-10-09", 6)),\(day("2026-10-10", 0))]},
  {"contributionDays":[\(day("2026-10-11", 1)),\(day("2026-10-12", 5))]}]}}},
 "pullRequests":{"issueCount":2},"reviewRequests":{"issueCount":1},"assignedIssues":{"issueCount":4}}}
""".utf8)

private func commit(_ date: String, _ added: Int, _ deleted: Int, parents: Int = 1, headline: String = "Change") -> String {
    #"{"oid":"\#(date)","messageHeadline":"\#(headline)","committedDate":"\#(date)","additions":\#(added),"deletions":\#(deleted),"parents":{"totalCount":\#(parents)}}"#
}

/// A repository's default-branch history, one page of it. R_1 is octo/one, R_2 octo/two.
private func repository(_ id: String, next cursor: String?, isPrivate: Bool = false, _ commits: [String]) -> String {
    let info = cursor.map { #"{"hasNextPage":true,"endCursor":"\#($0)"}"# } ?? #"{"hasNextPage":false,"endCursor":null}"#
    let name = ["R_1": "one", "R_2": "two", "R_3": "three"][id] ?? id
    return #"{"id":"\#(id)","name":"\#(name)","nameWithOwner":"octo/\#(name)","isPrivate":\#(isPrivate),"#
        + #""defaultBranchRef":{"target":{"history":{"pageInfo":\#(info),"nodes":[\#(commits.joined(separator: ","))]}}}}"#
}

// Five ordinary commits in one week, one of them vendored code, plus a merge. The
// second repository has another page, the third has no branch, and a repository
// GitHub could not resolve comes back null.
private let firstPages = Data("""
{"data":{"viewer":{"repositories":{"nodes":[
  \(repository("R_1", next: nil, [commit("2026-10-12T18:00:00Z", 10, 2), commit("2026-10-12T19:00:00Z", 5_000, 1_000, parents: 2),
                                  commit("2026-10-13T18:00:00Z", 20, 4), commit("2026-10-13T20:00:00Z", 30, 6)])),
  \(repository("R_2", next: "c1", isPrivate: true, [commit("2026-10-14T19:00:00Z", 9_000, 3_000), commit("2026-10-14T18:00:00Z", 40, 8)])),
  {"id":"R_3","name":"three","nameWithOwner":"octo/three","isPrivate":false,"defaultBranchRef":null},null]}}}}
""".utf8)

private let secondPage = Data("""
{"data":{"node":\(repository("R_2", next: nil, [commit("2026-09-30T18:00:00Z", 50, 10)]))}}
""".utf8)

private let now = losAngeles.date(from: DateComponents(year: 2026, month: 10, day: 15, hour: 12))!

@Test func theCalendarAndCountsDecode() throws {
    let github = try GitHubParsing.summary(from: summary, commits: [], truncated: false, calendar: losAngeles, now: now)
    #expect(github.login == "octo")
    #expect(github.contributions == [0, 3, 1, 0, 2, 0, 0, 0, 4, 0, 1, 0, 6, 0, 1, 5])
    #expect(github.levels == [0, 2, 1, 0, 1, 0, 0, 0, 3, 0, 1, 0, 4, 0, 1, 4])
    #expect(github.firstDay == losAngeles.date(from: DateComponents(year: 2026, month: 9, day: 27)))
    #expect(github.openPullRequests == 2 && github.reviewRequests == 1 && github.assignedIssues == 4)
    #expect(!github.linesTruncated)
}

@Test func mergesAreDroppedAndEachCommitIsClampedAtThe95thPercentile() throws {
    let commits = try GitHubParsing.histories(from: firstPages).flatMap(\.commits)
    let github = try GitHubParsing.summary(from: summary, commits: commits, truncated: false, calendar: losAngeles, now: now)
    #expect(github.weeks.count == 12)
    let thisWeek = try #require(github.weeks.last)
    #expect(thisWeek.start == losAngeles.date(from: DateComponents(year: 2026, month: 10, day: 11)))
    // Additions 10, 20, 30, 40 and 9,000: the 95th percentile, rounded down, is 40,
    // so the vendored commit counts as 40. Deletions likewise clamp at 8.
    #expect(thisWeek.added == 140)
    #expect(thisWeek.deleted == 28)
    #expect(github.weeks.dropLast().allSatisfy { $0.added == 0 && $0.deleted == 0 })
}

@Test func recentCommitsAreNewestFirstAcrossRepositoriesWithoutMerges() throws {
    let commits = try GitHubParsing.histories(from: firstPages).flatMap(\.commits)
    let github = try GitHubParsing.summary(from: summary, commits: commits, truncated: false, calendar: losAngeles, now: now)
    #expect(github.commits.map(\.repository) == ["two", "two", "one", "one", "one"])
    #expect(github.commits.map(\.oid) == ["2026-10-14T19:00:00Z", "2026-10-14T18:00:00Z", "2026-10-13T20:00:00Z",
                                         "2026-10-13T18:00:00Z", "2026-10-12T18:00:00Z"])
    let newest = try #require(github.commits.first)
    #expect(newest.additions == 9_000 && newest.deletions == 3_000)
    #expect(newest.date == ISO8601DateFormatter().date(from: "2026-10-14T19:00:00Z"))
}

/// Until the Mac fetches GitHub and applies its redaction list, a private repository
/// shows its name and line counts but never what a commit says.
@Test func aPrivateRepositorysHeadlinesStayOffTheTV() throws {
    let commits = try GitHubParsing.histories(from: firstPages).flatMap(\.commits)
    let github = try GitHubParsing.summary(from: summary, commits: commits, truncated: false, calendar: losAngeles, now: now)
    #expect(github.commits.filter { $0.repository == "two" }.allSatisfy { $0.headline == nil })
    #expect(github.commits.filter { $0.repository == "one" }.allSatisfy { $0.headline == "Change" })
}

@Test func onlyTheNewestTwentyCommitsAreKept() throws {
    let many = (0..<25).map { commit(String(format: "2026-10-1%dT%02d:00:00Z", $0 / 24 + 2, $0 % 24), 1, 1) }
    let pages = Data(#"{"data":{"viewer":{"repositories":{"nodes":[\#(repository("R_1", next: nil, many.reversed()))]}}}}"#.utf8)
    let commits = try GitHubParsing.histories(from: pages).flatMap(\.commits)
    let github = try GitHubParsing.summary(from: summary, commits: commits, truncated: false, calendar: losAngeles, now: now)
    #expect(github.commits.count == 20)
    #expect(github.commits.first?.oid == "2026-10-13T00:00:00Z")
    #expect(github.commits.last?.oid == "2026-10-12T05:00:00Z")
}

/// The repositories the viewer committed to most in the window, busiest first, by name.
@Test func repositoriesAreRankedByTheViewersOwnCommits() throws {
    let commits = try GitHubParsing.histories(from: firstPages).flatMap(\.commits)
    let github = try GitHubParsing.summary(from: summary, commits: commits, truncated: false, calendar: losAngeles, now: now)
    #expect(github.repositories == ["octo/one", "octo/two"])
}

/// A fork's code_frequency carries its upstream's whole history, so forks never count.
@Test func forksAreLeftOut() {
    #expect(GitHubParsing.historyQuery.contains("isFork: false"))
}

@Test func aBusyRepositoryIsReadPastItsFirstPage() async throws {
    let first = try GitHubParsing.histories(from: firstPages)
    #expect(first.map(\.repository) == ["R_1", "R_2"])
    #expect(first.map(\.next) == [nil, "c1"])

    let all = try await GitHubParsing.readAll(first, extraPages: 20) { history in
        #expect(history.repository == "R_2" && history.next == "c1")
        return try GitHubParsing.history(from: secondPage)
    }
    #expect(all.commits.count == 7)
    #expect(!all.truncated)
}

@Test func historiesLeftUnreadAreFlagged() async throws {
    let first = try GitHubParsing.histories(from: firstPages)
    let stillBusy = GitHubParsing.History(repository: "R_2", commits: [], next: "c2")
    #expect(try await GitHubParsing.readAll(first, extraPages: 1) { _ in stillBusy }.truncated)
    #expect(try await GitHubParsing.readAll(first, extraPages: 0) { _ in
        Issue.record("read a page past the budget")
        return stillBusy
    }.truncated)
}

@Test func weeksStartWhereThePlaceStartsThemAcrossAMidnightClockChange() throws {
    // Santiago springs forward at midnight, so Sunday 6 September 2026 starts at 01:00.
    var santiago = Calendar(identifier: .gregorian)
    santiago.timeZone = TimeZone(identifier: "America/Santiago")!
    let pages = Data("""
    {"data":{"viewer":{"repositories":{"nodes":[
      \(repository("R_1", next: nil, [commit("2026-09-01T15:00:00Z", 10, 1), commit("2026-09-07T15:00:00Z", 10, 1)]))]}}}}
    """.utf8)
    let commits = try GitHubParsing.histories(from: pages).flatMap(\.commits)
    let now = santiago.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 12))!
    let github = try GitHubParsing.summary(from: summary, commits: commits, truncated: false, calendar: santiago, now: now)
    #expect(github.weeks.suffix(2).map(\.added) == [10, 10])
    #expect(github.weeks.last?.start == santiago.date(from: DateComponents(year: 2026, month: 9, day: 6, hour: 1)))
}

@Test func aRefusedQueryReadsAsGitHubsMessage() {
    let limited = Data(#"{"data":null,"errors":[{"type":"RATE_LIMITED","message":"API rate limit exceeded for user ID 1."}]}"#.utf8)
    #expect(throws: FeedError.refused("API rate limit exceeded for user ID 1.")) {
        try GitHubParsing.histories(from: limited)
    }
    #expect(throws: FeedError.refused("API rate limit exceeded for user ID 1.")) {
        try GitHubParsing.summary(from: limited, commits: [], truncated: false, calendar: losAngeles, now: now)
    }
}

/// The calendar counts commits, pull requests, issues and reviews per day; a week is
/// its seven days from the calendar's Sunday.
@Test func contributionsAddUpByWeekFromTheCalendarsSundays() throws {
    let github = try GitHubParsing.summary(from: summary, commits: [], truncated: false, calendar: losAngeles, now: now)
    let weeks = github.contributionWeeks(calendar: losAngeles)
    #expect(weeks.map(\.count) == [6, 11, 6])
    let sundays = [DateComponents(year: 2026, month: 9, day: 27), DateComponents(year: 2026, month: 10, day: 4),
                   DateComponents(year: 2026, month: 10, day: 11)].map { losAngeles.date(from: $0)! }
    #expect(weeks.map(\.start) == sundays)
}

@Test func theLatest52WeeksAreCounted() {
    let github = Samples.github(at: now)
    let calendar = Samples.place.calendar
    let weeks = github.contributionWeeks(calendar: calendar)
    #expect(weeks.count == 52)
    #expect(weeks.last?.start == calendar.dateInterval(of: .weekOfYear, for: now)?.start)
    // The first of the calendar's 53 weeks is the one left out.
    let total: Int = weeks.map(\.count).reduce(0, +)
    let firstWeek: Int = github.contributions.prefix(7).reduce(0, +)
    #expect(total == github.totalContributions - firstWeek)
}

@Test func theAverageRunsOverTheFourWeeksEndingAtEach() {
    #expect(GitHubSummary.trailingAverage([4, 8, 0, 4, 12], over: 4) == [4, 6, 4, 4, 6])
    #expect(GitHubSummary.trailingAverage([], over: 4).isEmpty)
}
