import Foundation
import Testing
@testable import NorthlightKit

@Test func unreadThreadsDecodeNewestFirstWithTheirKindReasonAndNumber() throws {
    let (unread, newest) = try GitHubInboxParsing.notifications(from: fixture("github-notifications"), keepsPrivateTitles: false)
    #expect(unread == 5)
    #expect(newest.map(\.repository) == ["quillify", "acme-bid", "swift-format", "northlight", "aurora"])
    #expect(newest.map(\.kind) == [.pullRequest, .issue, .release, .checkSuite, .discussion])
    #expect(newest.map(\.reason) == ["review_requested", "mention", "subscribed", "ci_activity", "author"])
    // A release's address ends in an id, and a check suite has none.
    #expect(newest.map(\.number) == [285, 12, nil, nil, 7])
    #expect(newest.first?.updatedAt == utc("2026-10-19T17:02:11Z"))
}

/// The TV's own fetch never shows what a private repository's thread says; the Mac
/// keeps it and applies its redaction list.
@Test func aPrivateRepositorysThreadTitleStaysOffTheTV() throws {
    let tv = try GitHubInboxParsing.notifications(from: fixture("github-notifications"), keepsPrivateTitles: false).newest
    #expect(tv[1].title == nil)
    #expect(tv[0].title == "Bundle Carlito and Liberation fonts")
    let mac = try GitHubInboxParsing.notifications(from: fixture("github-notifications"), keepsPrivateTitles: true).newest
    #expect(mac[1].title == "Price the ACME bid before Friday")
}

@Test func readThreadsAreNotCountedAndOnlyTheNewestTenAreKept() throws {
    let thread = #"{"id":"%d","unread":%@,"reason":"subscribed","updated_at":"2026-10-19T%02d:00:00Z","subject":{"title":"t","url":null,"type":"Issue"},"repository":{"name":"r","private":false}}"#
    let threads = (0..<14).map { String(format: thread, $0, $0 == 13 ? "false" : "true", $0) }
    let (unread, newest) = try GitHubInboxParsing.notifications(from: Data("[\(threads.joined(separator: ","))]".utf8), keepsPrivateTitles: false)
    #expect(unread == 13)
    #expect(newest.map(\.id) == (3..<13).reversed().map(String.init))
}

@Test func pullRequestsWaitingOnTheViewerAndTheirOwnDecodeWithReviewAndChecks() throws {
    let pulls = try GitHubInboxParsing.pullRequests(from: fixture("github-pulls"), keepsPrivateTitles: false)
    #expect(pulls.reviewCount == 2 && pulls.authoredCount == 3)
    #expect(pulls.reviewRequests.map(\.number) == [285, 41])
    #expect(pulls.reviewRequests.map(\.review) == [.required, .none])
    #expect(pulls.reviewRequests.map(\.checks) == [.passing, .none])
    // A search hit that is not a pull request is left out.
    #expect(pulls.authored.map(\.number) == [312, 1224])
    #expect(pulls.authored.map(\.review) == [.changesRequested, .approved])
    #expect(pulls.authored.map(\.checks) == [.failing, .pending])
    #expect(pulls.authored.map(\.isDraft) == [false, true])
    #expect(pulls.authored.first?.updatedAt == utc("2026-10-19T16:45:00Z"))
}

@Test func aPrivateRepositorysPullRequestTitleStaysOffTheTV() throws {
    let tv = try GitHubInboxParsing.pullRequests(from: fixture("github-pulls"), keepsPrivateTitles: false)
    #expect(tv.reviewRequests.map(\.title) == ["Bundle Carlito and Liberation fonts", nil])
    let mac = try GitHubInboxParsing.pullRequests(from: fixture("github-pulls"), keepsPrivateTitles: true)
    #expect(mac.reviewRequests.last?.title == "Move the bid totals to the summary sheet")
}

@Test func theSearchesAskForOpenPullRequestsOnTheViewer() {
    #expect(GitHubInboxParsing.pullRequestsQuery.contains("is:pr is:open archived:false review-requested:@me"))
    #expect(GitHubInboxParsing.pullRequestsQuery.contains("is:pr is:open archived:false author:@me"))
}

@Test func anUnknownThreadKindFromANewerMacReadsAsOther() throws {
    #expect(try JSONDecoder().decode([GitHubInbox.Kind].self, from: Data(#"["issue","securityAdvisory"]"#.utf8)) == [.issue, .other])
}

extension CannedGitHubSuites {
    @Suite struct GitHubInboxFetchTests {
        private let pulls = String(decoding: try! fixture("github-pulls"), as: UTF8.self)
        private let threads = String(decoding: try! fixture("github-notifications"), as: UTF8.self)
        private let now = utc("2026-10-19T18:00:00Z")

        /// GitHub asks clients to wait X-Poll-Interval seconds between reads and to send
        /// Last-Modified back, answering 304 when nothing changed.
        @Test func notificationsAreAskedOnlyAsOftenAsGitHubAllowsAndOnlyForChanges() async throws {
            CannedGitHub.answers = ["/graphql": Array(repeating: (200, pulls), count: 3), "/notifications": [(200, threads), (304, "")]]
            CannedGitHub.headers = ["/notifications": ["Last-Modified": "Mon, 19 Oct 2026 17:02:11 GMT", "X-Poll-Interval": "60"]]
            CannedGitHub.asked = []
            defer { CannedGitHub.headers = [:] }
            let poll = GitHubNotificationPoll(), http = CannedGitHub.http()

            let first = try await http.githubInbox(token: "gho_test", poll: poll, now: now)
            #expect(first.unread == 5 && !first.moreUnread)
            #expect(first.reviewRequests.count == 2 && first.authored.count == 2)
            let second = try await http.githubInbox(token: "gho_test", poll: poll, now: now.addingTimeInterval(30))
            let third = try await http.githubInbox(token: "gho_test", poll: poll, now: now.addingTimeInterval(61))
            #expect(second == first && third == first)

            let asked = CannedGitHub.asked.filter { $0.url?.path() == "/notifications" }
            #expect(asked.count == 2)
            #expect(asked.first?.url?.query() == "per_page=50")
            #expect(asked.first?.value(forHTTPHeaderField: "Authorization") == "Bearer gho_test")
            #expect(asked.first?.value(forHTTPHeaderField: "If-Modified-Since") == nil)
            #expect(asked.last?.value(forHTTPHeaderField: "If-Modified-Since") == "Mon, 19 Oct 2026 17:02:11 GMT")
        }

        @Test func aNextPageMeansMoreUnreadThanCounted() async throws {
            CannedGitHub.answers = ["/graphql": [(200, pulls)], "/notifications": [(200, threads)]]
            CannedGitHub.headers = ["/notifications": ["Link": #"<https://api.github.com/notifications?per_page=50&page=2>; rel="next""#]]
            CannedGitHub.asked = []
            defer { CannedGitHub.headers = [:] }
            let inbox = try await CannedGitHub.http().githubInbox(token: "gho_test", poll: GitHubNotificationPoll(), now: now)
            #expect(inbox.moreUnread)
        }

        @Test func aRefusedTokenFailsTheRead() async throws {
            CannedGitHub.answers = ["/notifications": [(401, #"{"message":"Bad credentials"}"#)]]
            CannedGitHub.asked = []
            await #expect(throws: FeedError.badStatus(401)) {
                _ = try await CannedGitHub.http().githubInbox(token: "gho_test", poll: GitHubNotificationPoll(), now: now)
            }
        }
    }
}
