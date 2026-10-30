import Foundation
import Testing
@testable import NorthlightKit

/// Answers each repository's requests from its own queue of canned responses and
/// keeps what was asked.
final class CannedGitHub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var answers: [String: [(status: Int, body: String)]] = [:]
    nonisolated(unsafe) static var asked: [URLRequest] = []
    /// Headers for every answer to a path.
    nonisolated(unsafe) static var headers: [String: [String: String]] = [:]

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.asked.append(request)
        let path = request.url!.path()
        let answer: (status: Int, body: String) = Self.answers[path]?.isEmpty == false ? Self.answers[path]!.removeFirst() : (503, "")
        let response = HTTPURLResponse(url: request.url!, statusCode: answer.status, httpVersion: nil, headerFields: Self.headers[path])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(answer.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}

    static func http() -> HTTP {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CannedGitHub.self]
        return HTTP(userAgent: "test", configuration: configuration)
    }
}

/// Sundays at midnight UTC, as code_frequency gives its weeks.
private let t0 = 1_790_208_000, t1 = t0 + 604_800, t2 = t1 + 604_800
private let a = "/repos/octo/a/stats/code_frequency", b = "/repos/octo/b/stats/code_frequency"

/// Records the waits instead of sleeping through them.
private actor Waits {
    var seen: [Duration] = []
    func record(_ wait: Duration) { seen.append(wait) }
}

/// Every suite that answers through `CannedGitHub`, one test at a time, since its
/// answers are shared.
@Suite(.serialized) enum CannedGitHubSuites {}

extension CannedGitHubSuites {
    @Suite struct CodeHistoryTests {
        @Test func linesAddUpPerRepositoryAndInTotal() async throws {
            CannedGitHub.answers = [a: [(200, "[[\(t0),100,-10],[\(t1),50,-20]]")], b: [(200, "[[\(t1),30,0],[\(t2),5,-5]]")]]
            CannedGitHub.asked = []
            let history = try await CannedGitHub.http().codeHistory(token: "gho_test", repositories: ["octo/a", "octo/b"]) { _ in }
            #expect(history.repositories.map(\.name) == ["octo/a", "octo/b"])
            #expect(history.weekStarts == [t0, t1, t2].map { Date(timeIntervalSince1970: TimeInterval($0)) })
            #expect(history.lines(of: history.repositories[0]) == [90, 120, 120])
            #expect(history.lines(of: history.repositories[1]) == [0, 30, 30])
            #expect(history.totals == [90, 150, 150])
            #expect(history.repositories[0].weeks.map(\.deleted) == [10, 20])
            #expect(history.skipped.isEmpty)
        }

        @Test func eachRequestIsTheRepositorysCodeFrequencyWithTheToken() async throws {
            CannedGitHub.answers = [a: [(200, "[]")]]
            CannedGitHub.asked = []
            let history = try await CannedGitHub.http().codeHistory(token: "gho_test", repositories: ["octo/a"]) { _ in }
            #expect(history.totals.isEmpty)
            let request = try #require(CannedGitHub.asked.first)
            #expect(request.url?.absoluteString == "https://api.github.com\(a)")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer gho_test")
        }

        /// GitHub answers 202 while it computes a repository's statistics.
        @Test func aRepositoryStillComputingIsAskedAgainAfter45Seconds() async throws {
            CannedGitHub.answers = [a: [(202, "{}"), (200, "[[\(t0),7,-1]]")]]
            CannedGitHub.asked = []
            let waits = Waits()
            let history = try await CannedGitHub.http().codeHistory(token: "gho_test", repositories: ["octo/a"]) { await waits.record($0) }
            #expect(history.totals == [6])
            #expect(await waits.seen == [.seconds(45)])
            #expect(CannedGitHub.asked.count == 2)
        }

        @Test func threeAnswersOfStillComputingReadAsCounting() async throws {
            CannedGitHub.answers = [a: [(202, "{}"), (202, "{}"), (202, "{}")]]
            CannedGitHub.asked = []
            let waits = Waits()
            await #expect(throws: FeedError.refused(CodeHistory.counting)) {
                _ = try await CannedGitHub.http().codeHistory(token: "gho_test", repositories: ["octo/a"]) { await waits.record($0) }
            }
            #expect(await waits.seen == [.seconds(45), .seconds(45)])
            #expect(CannedGitHub.asked.count == 3)
            #expect(CodeHistory.counting == "GitHub is counting lines")
        }

        /// code_frequency refuses a repository with 10,000 commits or more.
        @Test func aRepositoryTooBigToCountIsSkippedAndNamed() async throws {
            CannedGitHub.answers = [a: [(200, "[[\(t0),100,-10]]")], b: [(422, #"{"message":"too many commits"}"#)]]
            CannedGitHub.asked = []
            let history = try await CannedGitHub.http().codeHistory(token: "gho_test", repositories: ["octo/a", "octo/b"]) { _ in }
            #expect(history.repositories.map(\.name) == ["octo/a"])
            #expect(history.skipped == ["octo/b"])
            #expect(history.totals == [90])
        }

        @Test func anEmptyRepositoryCountsNothing() async throws {
            CannedGitHub.answers = [a: [(204, "")], b: [(200, "[[\(t0),3,0]]")]]
            CannedGitHub.asked = []
            let history = try await CannedGitHub.http().codeHistory(token: "gho_test", repositories: ["octo/a", "octo/b"]) { _ in }
            #expect(history.totals == [3])
        }
    }
}
