import Foundation
import Testing
@testable import NorthlightKit

@Test func runsDecodeWithWorkflowBranchEventAndState() throws {
    let runs = try GitHubActionsParsing.runs(from: fixture("github-actions-runs"), keepsPrivateBranches: false)
    #expect(runs.map(\.workflow) == ["CI", "CI", "Release", "CI", "pages build and deployment"])
    #expect(runs.map(\.state) == [.running, .failed, .passed, .passed, .queued])
    #expect(runs.map(\.branch) == ["feature/inbox", "main", "main", "main", "gh-pages"])
    #expect(runs.map(\.event) == ["pull_request", "push", "workflow_dispatch", "push", "dynamic"])
    #expect(runs.allSatisfy { $0.repository == "northlight" })
    #expect(runs[1].createdAt == utc("2026-10-19T06:12:00Z"))
}

@Test func aRunLastsFromItsStartToItsLastUpdateOrToNowWhileItRuns() throws {
    let runs = try GitHubActionsParsing.runs(from: fixture("github-actions-runs"), keepsPrivateBranches: false)
    let now = utc("2026-10-19T17:15:02Z")
    #expect(runs[0].duration(asOf: now) == 300)
    #expect(runs[1].duration(asOf: now) == 542)
    // Still waiting for a runner.
    #expect(runs[4].duration(asOf: now) == nil)
}

@Test func conclusionsMapToFewStates() {
    let cases: [(String, String?, GitHubActions.State)] = [
        ("queued", nil, .queued), ("waiting", nil, .queued), ("in_progress", nil, .running),
        ("completed", "success", .passed), ("completed", "failure", .failed), ("completed", "timed_out", .failed),
        ("completed", "startup_failure", .failed), ("completed", "cancelled", .cancelled), ("completed", "skipped", .skipped),
        ("completed", "neutral", .skipped),
    ]
    for (status, conclusion, state) in cases {
        #expect(GitHubActions.State(status: status, conclusion: conclusion) == state)
    }
}

/// A run under way does not hide the failure it may yet fix.
@Test func aWorkflowFailsUntilARunOfItPasses() throws {
    let runs = try GitHubActionsParsing.runs(from: fixture("github-actions-runs"), keepsPrivateBranches: false)
    let actions = GitHubActions(runs: runs.sorted { $0.createdAt > $1.createdAt }, repositories: ["octo/northlight"])
    #expect(actions.latest.map(\.workflow) == ["pages build and deployment", "CI", "Release"])
    #expect(actions.failing.map(\.id) == [18523100442])
    #expect(actions.underWay.map(\.workflow) == ["pages build and deployment", "CI"])
}

@Test func aPrivateRepositorysBranchStaysOffTheTV() throws {
    let data = Data(#"{"total_count":1,"workflow_runs":[{"id":1,"name":"CI","head_branch":"acme-bid-pricing","event":"push","status":"completed","conclusion":"success","created_at":"2026-10-19T06:12:00Z","updated_at":"2026-10-19T06:13:00Z","run_started_at":"2026-10-19T06:12:00Z","repository":{"name":"tools","private":true}}]}"#.utf8)
    #expect(try GitHubActionsParsing.runs(from: data, keepsPrivateBranches: false).first?.branch == nil)
    #expect(try GitHubActionsParsing.runs(from: data, keepsPrivateBranches: true).first?.branch == "acme-bid-pricing")
}

@Test func anUnknownRunStateFromANewerMacCountsForNothing() throws {
    #expect(try JSONDecoder().decode([GitHubActions.State].self, from: Data(#"["failed","awaitingDeploy"]"#.utf8)) == [.failed, .skipped])
}

extension CannedGitHubSuites {
    @Suite struct GitHubActionsFetchTests {
        @Test func eachRepositorysFiveNewestRunsAreMergedNewestFirst() async throws {
            let one = String(decoding: try fixture("github-actions-runs"), as: UTF8.self)
            let two = #"{"total_count":1,"workflow_runs":[{"id":9,"name":"Test","head_branch":"main","event":"push","status":"completed","conclusion":"success","created_at":"2026-10-19T12:00:00Z","updated_at":"2026-10-19T12:02:00Z","run_started_at":"2026-10-19T12:00:10Z","repository":{"name":"quillify","private":false}}]}"#
            CannedGitHub.answers = ["/repos/octo/northlight/actions/runs": [(200, one)], "/repos/octo/quillify/actions/runs": [(200, two)],
                                    "/repos/octo/gone/actions/runs": [(404, #"{"message":"Not Found"}"#)]]
            CannedGitHub.asked = []
            let actions = try await CannedGitHub.http().githubActions(token: "gho_test",
                                                                       repositories: ["octo/northlight", "octo/gone", "octo/quillify"])
            #expect(actions.runs.map(\.id) == [18520000111, 18523377001, 9, 18523100442, 18522001234, 18521000999])
            #expect(actions.repositories == ["octo/northlight", "octo/gone", "octo/quillify"])
            #expect(CannedGitHub.asked.first?.url?.query() == "per_page=5")
            #expect(CannedGitHub.asked.first?.value(forHTTPHeaderField: "Authorization") == "Bearer gho_test")
        }

        @Test func aRefusedTokenFailsTheRead() async throws {
            CannedGitHub.answers = ["/repos/octo/northlight/actions/runs": [(401, #"{"message":"Bad credentials"}"#)]]
            CannedGitHub.asked = []
            await #expect(throws: FeedError.badStatus(401)) {
                _ = try await CannedGitHub.http().githubActions(token: "gho_test", repositories: ["octo/northlight"])
            }
        }
    }
}
