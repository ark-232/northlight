import Foundation
import Testing
@testable import NorthlightKit

private let token = ProcessInfo.processInfo.environment["NORTHLIGHT_GITHUB_TOKEN"] ?? ""

/// Asks GitHub itself, so it runs only with a token:
///   NORTHLIGHT_GITHUB_TOKEN=$(gh auth token) swift test --filter GitHubLive
@Test(.enabled(if: !token.isEmpty))
func gitHubAnswersTheQueries() async throws {
    let github = try await HTTP(userAgent: "Northlight tests").github(token: token, calendar: .current)
    #expect(github.contributions.count > 360)
    #expect(github.weeks.count == 12)
    print("weeks added", github.weeks.map(\.added), "deleted", github.weeks.map(\.deleted), "truncated", github.linesTruncated)
    #expect(github.levels.count == github.contributions.count)
    print("commits", github.commits.count, "repositories", github.repositories.prefix(5))
    let lines = try await HTTP(userAgent: "Northlight tests").codeHistory(token: token, repositories: Array(github.repositories.prefix(5)))
    print("lines", lines.totals.last ?? 0, "in", lines.repositories.map(\.name), "skipped", lines.skipped)
    #expect(github.contributionWeeks(calendar: .current).count == 52)

    let inbox = try await HTTP(userAgent: "Northlight tests").githubInbox(token: token, poll: GitHubNotificationPoll())
    #expect(inbox.notifications.count <= 10)
    print("unread", inbox.unread, inbox.moreUnread ? "or more" : "", "kinds", inbox.notifications.map(\.kind.rawValue),
          "to review", inbox.reviewRequestCount, "yours", inbox.authoredCount, "checks", inbox.authored.map(\.checks.rawValue))
    let actions = try await HTTP(userAgent: "Northlight tests").githubActions(token: token, repositories: Array(github.repositories.prefix(5)))
    #expect(actions.runs.count <= 25)
    print("runs", actions.runs.count, "states", actions.runs.map(\.state.rawValue), "failing", actions.failing.map(\.workflow))
}
