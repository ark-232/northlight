import Foundation
import Testing
@testable import NorthlightKit

private let summary = #"""
{"data":{"viewer":{"id":"U_1","login":"octo","contributionsCollection":{"contributionCalendar":{"weeks":[
  {"contributionDays":[{"date":"2026-10-18","contributionCount":2,"contributionLevel":"SECOND_QUARTILE"}]}]}}},
 "pullRequests":{"issueCount":1},"reviewRequests":{"issueCount":0},"assignedIssues":{"issueCount":2}}}
"""#

private func commit(_ oid: String) -> String {
    #"{"oid":"\#(oid)","messageHeadline":"Change","committedDate":"2026-10-18T18:00:00Z","additions":3,"deletions":1,"parents":{"totalCount":1}}"#
}

private func repository(_ name: String, _ commits: [String]) -> String {
    #"{"id":"R_\#(name)","name":"\#(name)","nameWithOwner":"octo/\#(name)","isPrivate":false,"defaultBranchRef":{"target":{"history":{"#
        + #""pageInfo":{"hasNextPage":false,"endCursor":null},"nodes":[\#(commits.joined(separator: ","))]}}}}"#
}

/// The viewer committed twice to octo/two and once to octo/one.
private let histories = #"{"data":{"viewer":{"repositories":{"nodes":["#
    + repository("one", [commit("a")]) + "," + repository("two", [commit("b"), commit("c")]) + "]}}}}"

private let codeFrequency = "/repos/octo/one/stats/code_frequency"
private let codeFrequencyTwo = "/repos/octo/two/stats/code_frequency"

private func config(token: String?) -> Config {
    var config = Config(place: Place(name: "Reykjavík", latitude: 64.1466, longitude: -21.9426,
                                     timeZoneIdentifier: "Atlantic/Reykjavik", countryCode: "IS"),
                        calendarICSURL: nil, contact: "test")
    config.githubToken = token
    return config
}

/// A cache directory of the test's own, never the app's.
private func scratchCache() -> Cache {
    Cache(name: "NorthlightTests/\(UUID().uuidString)")
}

/// Writes `value` as the cache would have, at `fetchedAt`.
private func plant<T: Codable>(_ value: T, as key: String, in cache: Cache, fetchedAt: Date) throws {
    try JSONEncoder().encode(Cache.Stamped(fetchedAt: fetchedAt, value: value)).write(to: cache.url(for: key))
}

private let cachedSummary = Samples.github(at: Date())
private let cachedLines = CodeHistory(repositories: [.init(name: "octo/one", weeks: [.init(start: Date(timeIntervalSince1970: 1_790_208_000), added: 40, deleted: 2)])],
                                      skipped: [])

@MainActor
private func waitFor(_ condition: () -> Bool) async throws {
    for _ in 0..<200 where !condition() {
        try await Task.sleep(for: .milliseconds(25))
    }
    try #require(condition())
}

extension CannedGitHubSuites {
    @MainActor @Suite struct GitHubStoreTests {
        @Test func linesComeFromTheViewersBusiestRepositoriesAtMostOnceADay() async throws {
            CannedGitHub.answers = ["/graphql": [(200, summary), (200, histories), (200, summary), (200, histories)],
                                    codeFrequency: [(200, "[[1790208000,10,0]]")], codeFrequencyTwo: [(200, "[[1790208000,5,-1]]")]]
            CannedGitHub.asked = []
            let caches = scratchCache()
            defer { caches.clear() }
            let store = DashboardStore(config: config(token: "gho_test"), http: CannedGitHub.http(), githubCaches: caches)
            defer { store.stop() }
            store.run([.github(token: "gho_test")])
            try await waitFor { store.codeHistory.value != nil }
            #expect(store.codeHistory.value?.repositories.map(\.name) == ["octo/two", "octo/one"])
            #expect(store.codeHistory.value?.totals == [14])

            store.refreshAll()
            try await waitFor { CannedGitHub.asked.filter { $0.url?.path() == "/graphql" }.count == 4 }
            try await Task.sleep(for: .milliseconds(200))
            #expect(CannedGitHub.asked.filter { $0.url?.path().hasSuffix("code_frequency") == true }.count == 2)
        }

        /// A relaunch shows the last summary and lines with their age rather than Loading,
        /// and asks GitHub for no lines while they are under a day old.
        @Test func theCacheLoadsStaleAtLaunch() async throws {
            CannedGitHub.answers = [:]
            CannedGitHub.asked = []
            let caches = scratchCache()
            defer { caches.clear() }
            let account = DashboardStore.githubCache(token: "gho_test", in: caches)
            let now = Date()
            try plant(cachedSummary, as: "summary", in: account, fetchedAt: now.addingTimeInterval(-3 * 86_400))
            try plant(cachedLines, as: "lines", in: account, fetchedAt: now.addingTimeInterval(-2 * 3_600))

            let store = DashboardStore(config: config(token: "gho_test"), http: CannedGitHub.http(), githubCaches: caches)
            defer { store.stop() }
            store.run([.github(token: "gho_test")])
            try await waitFor { store.github.value != nil && store.codeHistory.value != nil }
            #expect(store.github.value == cachedSummary)
            #expect(store.github.staleAge(asOf: now) != nil)
            #expect(store.codeHistory.value == cachedLines)
            #expect(CannedGitHub.asked.allSatisfy { $0.url?.path().hasSuffix("code_frequency") == false })
        }

        /// The cache holds commit headlines, so it goes with the account.
        @Test func disconnectingClearsTheCache() throws {
            let caches = scratchCache()
            defer { caches.clear() }
            let account = DashboardStore.githubCache(token: "gho_test", in: caches)
            try plant(cachedSummary, as: "summary", in: account, fetchedAt: Date())
            #expect(FileManager.default.fileExists(atPath: account.url(for: "summary").path()))

            _ = DashboardStore(config: config(token: nil), http: CannedGitHub.http(), githubCaches: caches)
            #expect(!FileManager.default.fileExists(atPath: account.url(for: "summary").path()))
        }

        /// The runs come from the same repositories as the lines: the viewer's busiest.
        @Test func runsComeFromTheViewersBusiestRepositories() async throws {
            let runs = #"{"total_count":0,"workflow_runs":[]}"#
            CannedGitHub.answers = ["/graphql": [(200, summary), (200, histories)],
                                    codeFrequency: [(200, "[]")], codeFrequencyTwo: [(200, "[]")],
                                    "/repos/octo/one/actions/runs": [(200, runs)], "/repos/octo/two/actions/runs": [(200, runs)]]
            CannedGitHub.asked = []
            let caches = scratchCache()
            defer { caches.clear() }
            let store = DashboardStore(config: config(token: "gho_test"), http: CannedGitHub.http(), githubCaches: caches)
            defer { store.stop() }
            store.run([.github(token: "gho_test"), .githubActions(token: "gho_test")])
            try await waitFor { store.githubActions.value != nil }
            #expect(store.githubActions.value?.repositories == ["octo/two", "octo/one"])
        }

        @Test func theInboxRunsOnItsOwn() async throws {
            let pulls = String(decoding: try fixture("github-pulls"), as: UTF8.self)
            let threads = String(decoding: try fixture("github-notifications"), as: UTF8.self)
            CannedGitHub.answers = ["/graphql": [(200, pulls)], "/notifications": [(200, threads)]]
            CannedGitHub.asked = []
            let caches = scratchCache()
            defer { caches.clear() }
            let store = DashboardStore(config: config(token: "gho_test"), http: CannedGitHub.http(), githubCaches: caches)
            defer { store.stop() }
            store.run([.githubInbox(token: "gho_test")])
            try await waitFor { store.githubInbox.value != nil }
            #expect(store.githubInbox.value?.unread == 5)
            #expect(store.githubInboxFeed(asOf: Date())?.value?.reviewRequests.map(\.number) == [285, 41])
            #expect(store.github.value == nil)
        }

        @Test func anotherAccountNeverSeesTheCache() async throws {
            CannedGitHub.answers = [:]
            CannedGitHub.asked = []
            let caches = scratchCache()
            defer { caches.clear() }
            try plant(cachedSummary, as: "summary", in: DashboardStore.githubCache(token: "gho_first", in: caches), fetchedAt: Date())

            let store = DashboardStore(config: config(token: "gho_second"), http: CannedGitHub.http(), githubCaches: caches)
            defer { store.stop() }
            store.run([.github(token: "gho_second")])
            try await waitFor { store.github.lastError != nil }
            #expect(store.github.value == nil)
        }
    }
}
