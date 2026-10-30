import Foundation
import NorthlightKit

/// Decides whether a session's detail may be shown on a screen in a shared room.
///
/// A blocklist, by the owner's choice, which fails open: a project shows until its
/// path matches one of the fragments the Mac's user lists in the app's settings.
/// Matching runs over the whole path, so a nested directory cannot slip past.
public struct AgentRedaction: Sendable {
    public var blockedPathFragments: [String]

    public init(blockedPathFragments: [String]) {
        self.blockedPathFragments = blockedPathFragments
    }

    public func isBlocked(path: String?) -> Bool {
        guard let path else { return false }
        let lowered = path.lowercased()
        return blockedPathFragments.contains { lowered.contains($0.lowercased()) }
    }

    /// Strips everything that could identify or quote the work, keeping only the
    /// shape of the activity so the tile still reads as busy.
    public func redact(_ status: AgentStatus) -> AgentStatus {
        var redacted = status
        redacted.project = nil
        redacted.branch = nil
        redacted.thinking = nil
        redacted.toolTarget = nil
        redacted.toolName = nil
        redacted.verb = status.activity == .idle ? "Idle" : "Working"
        redacted.redacted = true
        return redacted
    }

    /// What a blocked repository reads as on the TV.
    public static let privateRepository = "Private"

    /// The GitHub account with every blocked repository renamed and every blocked
    /// commit's headline dropped. A commit is blocked by its repository's name or
    /// by its own headline; its line counts stay, so the tile still adds up.
    public func redact(_ push: GitHubPush) -> GitHubPush {
        var redacted = push
        redacted.summary.commits = push.summary.commits.map { commit in
            var commit = commit
            if isBlocked(path: commit.repository) {
                commit.repository = Self.privateRepository
                commit.headline = nil
            } else if isBlocked(path: commit.headline) {
                commit.headline = nil
            }
            return commit
        }
        redacted.summary.repositories = push.summary.repositories.filter { !isBlocked(path: $0) }
        redacted.codeHistory = push.codeHistory.map { history in
            var history = history
            history.repositories = history.repositories.map { repository in
                var repository = repository
                if isBlocked(path: repository.name) { repository.name = Self.privateRepository }
                return repository
            }
            history.skipped = history.skipped.filter { !isBlocked(path: $0) }
            return history
        }
        redacted.inbox = push.inbox.map { inbox in
            var inbox = inbox
            inbox.notifications = inbox.notifications.map { thread in
                var thread = thread
                redact(&thread.repository, &thread.title)
                return thread
            }
            inbox.reviewRequests = inbox.reviewRequests.map(redact)
            inbox.authored = inbox.authored.map(redact)
            return inbox
        }
        redacted.actions = push.actions.map { actions in
            var actions = actions
            actions.runs = actions.runs.map { run in
                var run = run
                redact(&run.repository, &run.branch)
                return run
            }
            actions.repositories = actions.repositories.filter { !isBlocked(path: $0) }
            return actions
        }
        return redacted
    }

    private func redact(_ pull: GitHubInbox.PullRequest) -> GitHubInbox.PullRequest {
        var pull = pull
        redact(&pull.repository, &pull.title)
        return pull
    }

    /// A blocked repository is renamed and its words dropped; words blocked on their
    /// own are dropped alone.
    private func redact(_ repository: inout String, _ words: inout String?) {
        if isBlocked(path: repository) {
            repository = Self.privateRepository
            words = nil
        } else if isBlocked(path: words) {
            words = nil
        }
    }
}
