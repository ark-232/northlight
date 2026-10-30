import Foundation

/// The latest GitHub Actions runs in the viewer's busiest repositories.
public struct GitHubActions: Codable, Sendable, Equatable {
    /// Newest first across every repository asked.
    public var runs: [Run]
    /// The repositories asked, by owner and name.
    public var repositories: [String]

    public init(runs: [Run], repositories: [String]) {
        self.runs = runs
        self.repositories = repositories
    }

    public struct Run: Codable, Sendable, Equatable {
        public var id: Int
        /// The repository's name without its owner.
        public var repository: String
        public var workflow: String
        /// Nil for a private repository on the TV's own fetch, since a branch can name the work.
        public var branch: String?
        /// What started it, such as "push" or "pull_request".
        public var event: String
        public var state: State
        public var createdAt: Date
        /// Nil while it waits for a runner.
        public var startedAt: Date?
        public var updatedAt: Date

        public init(id: Int, repository: String, workflow: String, branch: String?, event: String, state: State,
                    createdAt: Date, startedAt: Date?, updatedAt: Date) {
            self.id = id
            self.repository = repository
            self.workflow = workflow
            self.branch = branch
            self.event = event
            self.state = state
            self.createdAt = createdAt
            self.startedAt = startedAt
            self.updatedAt = updatedAt
        }

        /// How long it ran, or has run so far; nil before it starts.
        public func duration(asOf now: Date) -> TimeInterval? {
            startedAt.map { max(0, (state.isFinished ? updatedAt : now).timeIntervalSince($0)) }
        }
    }

    public enum State: String, Codable, Sendable {
        case queued, running, passed, failed, cancelled, skipped

        var isFinished: Bool { self != .queued && self != .running }

        /// A state a newer Mac knows reads as skipped here, which counts for nothing.
        public init(from decoder: any Decoder) throws {
            self = State(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .skipped
        }

        init(status: String, conclusion: String?) {
            switch (status, conclusion) {
            case ("in_progress", _): self = .running
            case ("completed", "success"): self = .passed
            case ("completed", "failure"), ("completed", "timed_out"), ("completed", "startup_failure"): self = .failed
            case ("completed", "cancelled"): self = .cancelled
            case ("completed", _): self = .skipped
            default: self = .queued
            }
        }
    }

    /// The newest run of each workflow in each repository, newest first: what is
    /// passing or failing now, without the runs it replaced.
    public var latest: [Run] {
        var seen = Set<String>()
        return runs.filter { seen.insert("\($0.repository)\u{0}\($0.workflow)").inserted }
    }

    /// Workflows whose newest run that passed or failed, failed; a run under way
    /// does not clear the failure before it.
    public var failing: [Run] {
        var seen = Set<String>()
        return runs.filter { ($0.state == .passed || $0.state == .failed) && seen.insert("\($0.repository)\u{0}\($0.workflow)").inserted }
            .filter { $0.state == .failed }
    }

    /// Workflows whose newest run is queued or running.
    public var underWay: [Run] { latest.filter { !$0.state.isFinished } }
}

enum GitHubActionsParsing {
    static func runs(from data: Data, keepsPrivateBranches: Bool) throws -> [GitHubActions.Run] {
        struct Answer: Decodable {
            struct Run: Decodable {
                struct Repository: Decodable { var name: String; var `private`: Bool }
                var id: Int
                var name: String?
                var head_branch: String?
                var event: String
                var status: String?
                var conclusion: String?
                var created_at: String
                var updated_at: String
                var run_started_at: String?
                var repository: Repository
            }
            var workflow_runs: [Run]
        }
        let iso = ISO8601DateFormatter()
        return try decodeFeed(Answer.self, from: data).workflow_runs.compactMap { run in
            guard let created = iso.date(from: run.created_at), let updated = iso.date(from: run.updated_at) else { return nil }
            return GitHubActions.Run(id: run.id, repository: run.repository.name, workflow: run.name ?? "Workflow",
                                     branch: run.repository.private && !keepsPrivateBranches ? nil : run.head_branch,
                                     event: run.event, state: GitHubActions.State(status: run.status ?? "", conclusion: run.conclusion),
                                     createdAt: created, startedAt: run.run_started_at.flatMap(iso.date(from:)), updatedAt: updated)
        }
    }
}

extension HTTP {
    /// The five newest runs in each of `repositories`, one after another. A
    /// repository GitHub no longer shows the viewer is left out. Private repositories'
    /// branches stay off unless `keepsPrivateBranches`, for a caller that redacts them itself.
    public func githubActions(token: String, repositories: [String], keepsPrivateBranches: Bool = false) async throws -> GitHubActions {
        var runs: [GitHubActions.Run] = []
        for name in repositories {
            var request = URLRequest(url: makeURL("https://api.github.com/repos/\(name)/actions/runs", ["per_page": "5"]))
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            do {
                runs += try GitHubActionsParsing.runs(from: try await send(request), keepsPrivateBranches: keepsPrivateBranches)
            } catch FeedError.badStatus(404) {}
        }
        return GitHubActions(runs: runs.sorted { $0.createdAt > $1.createdAt }, repositories: repositories)
    }
}
