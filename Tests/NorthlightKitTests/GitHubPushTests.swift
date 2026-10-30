import Foundation
import Testing
@testable import NorthlightAgent
@testable import NorthlightKit

private let now = Date(timeIntervalSince1970: 1_800_000_000)

private func commit(_ repository: String, _ headline: String?) -> GitHubSummary.Commit {
    GitHubSummary.Commit(oid: repository, repository: repository, headline: headline, date: now, additions: 3, deletions: 1)
}

private func push() -> GitHubPush {
    var summary = Samples.github(at: now)
    summary.commits = [commit("northlight", "Stretch the page dot"), commit("acme-bid", "Price the bid"),
                       commit("tools", "Draft the ACME memo"), commit("dotfiles", nil)]
    summary.repositories = ["octo/northlight", "octo/acme-bid", "octo/tools"]
    let history = CodeHistory(repositories: [.init(name: "octo/northlight", weeks: []), .init(name: "octo/acme-bid", weeks: [])],
                              skipped: ["octo/acme-mono", "octo/huge"])
    return GitHubPush(summary: summary, codeHistory: history)
}

@Test func anEmptyRedactionListLeavesThePushAsItIs() {
    #expect(AgentRedaction(blockedPathFragments: []).redact(push()) == push())
}

@Test func aBlockedNameHidesTheRepositoryAndItsHeadlines() {
    let redacted = AgentRedaction(blockedPathFragments: ["Acme"]).redact(push())
    let commits = redacted.summary.commits
    #expect(commits[0].repository == "northlight")
    #expect(commits[0].headline == "Stretch the page dot")
    // Blocked by the repository's name.
    #expect(commits[1].repository == AgentRedaction.privateRepository)
    #expect(commits[1].headline == nil)
    // Blocked by the headline alone: the repository still shows, the words do not.
    #expect(commits[2].repository == "tools")
    #expect(commits[2].headline == nil)
    #expect(commits[3] == push().summary.commits[3])
    #expect(commits.map(\.additions) == push().summary.commits.map(\.additions))
    #expect(redacted.summary.repositories == ["octo/northlight", "octo/tools"])
}

@Test func aBlockedNameIsRenamedInTheLinesOfCode() {
    let history = AgentRedaction(blockedPathFragments: ["acme"]).redact(push()).codeHistory
    #expect(history?.repositories.map(\.name) == ["octo/northlight", AgentRedaction.privateRepository])
    #expect(history?.skipped == ["octo/huge"])
}

private func inboxPush() -> GitHubPush {
    func pull(_ repository: String, _ number: Int, _ title: String?) -> GitHubInbox.PullRequest {
        GitHubInbox.PullRequest(repository: repository, number: number, title: title, updatedAt: now, isDraft: false,
                                review: .required, checks: .passing)
    }
    func thread(_ repository: String, _ title: String?) -> GitHubInbox.Notification {
        GitHubInbox.Notification(id: repository, repository: repository, title: title, kind: .issue, reason: "mention",
                                 number: 1, updatedAt: now)
    }
    func run(_ repository: String, _ branch: String?) -> GitHubActions.Run {
        GitHubActions.Run(id: repository.count, repository: repository, workflow: "CI", branch: branch, event: "push",
                          state: .failed, createdAt: now, startedAt: now, updatedAt: now)
    }
    var push = push()
    push.inbox = GitHubInbox(unread: 2, moreUnread: false,
                             notifications: [thread("northlight", "Stretch the page dot"), thread("acme-bid", "Price the bid"),
                                             thread("tools", "Draft the ACME memo")],
                             reviewRequests: [pull("acme-bid", 4, "Bid totals"), pull("quillify", 285, "Bundle fonts")],
                             reviewRequestCount: 2, authored: [pull("tools", 9, "ACME export")], authoredCount: 1)
    push.actions = GitHubActions(runs: [run("northlight", "main"), run("acme-bid", "main"), run("tools", "acme-pricing")],
                                 repositories: ["octo/northlight", "octo/acme-bid", "octo/tools"])
    return push
}

@Test func aBlockedNameHidesTheInboxsRepositoryAndTitles() throws {
    let inbox = try #require(AgentRedaction(blockedPathFragments: ["acme"]).redact(inboxPush()).inbox)
    #expect(inbox.notifications.map(\.repository) == ["northlight", AgentRedaction.privateRepository, "tools"])
    #expect(inbox.notifications.map(\.title) == ["Stretch the page dot", nil, nil])
    #expect(inbox.reviewRequests.map(\.repository) == [AgentRedaction.privateRepository, "quillify"])
    #expect(inbox.reviewRequests.map(\.title) == [nil, "Bundle fonts"])
    #expect(inbox.authored.map(\.title) == [nil])
    #expect(inbox.unread == 2 && inbox.reviewRequestCount == 2)
}

@Test func aBlockedNameHidesTheRunsRepositoryAndBranch() throws {
    let actions = try #require(AgentRedaction(blockedPathFragments: ["acme"]).redact(inboxPush()).actions)
    #expect(actions.runs.map(\.repository) == ["northlight", AgentRedaction.privateRepository, "tools"])
    #expect(actions.runs.map(\.branch) == ["main", nil, nil])
    #expect(actions.runs.map(\.state) == [.failed, .failed, .failed])
    #expect(actions.repositories == ["octo/northlight", "octo/tools"])
}

/// An older Mac sends neither, and its push still reads.
@Test func aPushWithoutTheInboxOrActionsDecodes() throws {
    var fields = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(inboxPush())) as? [String: Any])
    fields["inbox"] = nil
    fields["actions"] = nil
    let decoded = try JSONDecoder().decode(GitHubPush.self, from: JSONSerialization.data(withJSONObject: fields))
    #expect(decoded == push())
}

extension CannedGitHubSuites {
    @Suite struct DeviceFlowSignInTests {
        @Test func signInShowsTheCodeThenWaitsForTheToken() async throws {
            CannedGitHub.answers = [
                "/login/device/code": [(200, #"{"device_code":"dc","user_code":"WDJB-MJHT","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#)],
                "/login/oauth/access_token": [(200, #"{"error":"authorization_pending"}"#), (200, #"{"access_token":"gho_abc"}"#)],
            ]
            CannedGitHub.asked = []
            let shown = Shown()
            let token = try await GitHubDeviceFlow.signIn(http: CannedGitHub.http(), onCode: { await shown.record($0.userCode) },
                                                          wait: { _ in })
            #expect(token == "gho_abc")
            #expect(CannedGitHub.asked.count == 3)
            #expect(await shown.codes == ["WDJB-MJHT"])
        }

        @Test func aCancelledSignInFailsWithGitHubsReason() async throws {
            CannedGitHub.answers = [
                "/login/device/code": [(200, #"{"device_code":"dc","user_code":"WDJB-MJHT","verification_uri":"https://github.com/login/device","expires_in":900,"interval":5}"#)],
                "/login/oauth/access_token": [(200, #"{"error":"access_denied"}"#)],
            ]
            await #expect(throws: FeedError.self) {
                try await GitHubDeviceFlow.signIn(http: CannedGitHub.http(), onCode: { _ in }, wait: { _ in })
            }
        }
    }
}

private actor Shown {
    var codes: [String] = []
    func record(_ code: String) { codes.append(code) }
}
