import NorthlightKit
import SwiftUI

/// What is waiting on the viewer on GitHub: the unread count, then pull requests
/// asking for their review, their own with how checks and review stand, and at large
/// size the newest threads.
struct GitHubInboxTile: View {
    /// Nil until an account is connected here or on the Mac.
    let feed: Loaded<GitHubInbox>?
    let now: Date
    @Environment(\.widgetSize) private var size

    var body: some View {
        Tile(label: "GitHub inbox", trailing: feed?.trailing(asOf: now)) {
            if let feed {
                FeedBody(state: feed.state(asOf: now)) { inbox in
                    VStack(alignment: .leading, spacing: size == .large ? 20 : 14) {
                        InboxHeadline(inbox: inbox)
                        if size == .large {
                            large(inbox)
                        } else {
                            medium(inbox)
                        }
                    }
                }
            } else {
                GitHubNotConnected()
            }
        }
    }

    /// Two rows: the reviews asked of the viewer first, then their own pull requests,
    /// else the newest threads.
    @ViewBuilder private func medium(_ inbox: GitHubInbox) -> some View {
        let pulls = inbox.reviewRequests.map { ($0, true) } + inbox.authored.map { ($0, false) }
        if !pulls.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(pulls.prefix(2), id: \.0.id) { pull, waiting in
                    PullRow(pull: pull, waitingOnYou: waiting, now: now)
                }
            }
        } else if !inbox.notifications.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(inbox.notifications.prefix(2), id: \.id) { ThreadRow(thread: $0, now: now) }
            }
        } else {
            TilePlaceholder(text: "Nothing waiting on you")
        }
    }

    /// Up to six rows in sections, the reviews and the viewer's own taking two each.
    @ViewBuilder private func large(_ inbox: GitHubInbox) -> some View {
        let reviews = Array(inbox.reviewRequests.prefix(2)), own = Array(inbox.authored.prefix(2))
        let threads = Array(inbox.notifications.prefix(6 - reviews.count - own.count))
        if reviews.isEmpty && own.isEmpty && threads.isEmpty {
            TilePlaceholder(text: "Nothing waiting on you")
        } else {
            VStack(alignment: .leading, spacing: 20) {
                if !reviews.isEmpty {
                    InboxSection(title: "Waiting on your review") {
                        ForEach(reviews, id: \.id) { PullRow(pull: $0, waitingOnYou: true, now: now) }
                    }
                }
                if !own.isEmpty {
                    InboxSection(title: "Your pull requests") {
                        ForEach(own, id: \.id) { PullRow(pull: $0, waitingOnYou: false, now: now) }
                    }
                }
                if !threads.isEmpty {
                    InboxSection(title: "Notifications") {
                        ForEach(threads, id: \.id) { ThreadRow(thread: $0, now: now) }
                    }
                }
            }
        }
    }
}

extension GitHubInbox.PullRequest {
    var id: String { "\(repository)#\(number)" }
}

/// "9 unread   2 to review · 3 yours".
private struct InboxHeadline: View {
    let inbox: GitHubInbox

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(inbox.moreUnread ? "\(inbox.unread)+" : "\(inbox.unread)")
                .font(Theme.Font.tileValue)
                .foregroundStyle(Theme.Palette.bone)
                .numericChange(inbox.unread)
            Text("unread")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.muted)
            Spacer(minLength: 12)
            Text("\(inbox.reviewRequestCount) to review · \(inbox.authoredCount) yours")
                .font(Theme.Font.body)
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.bone)
                .lineLimit(1)
                .numericChange([inbox.reviewRequestCount, inbox.authoredCount])
        }
    }
}

private struct InboxSection<Rows: View>: View {
    let title: String
    @ViewBuilder let rows: Rows

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(Theme.Font.label)
                .foregroundStyle(Theme.Palette.muted)
            rows
        }
    }
}

/// A pull request's title over its repository, number, checks, review and age. A
/// private repository's title is withheld and reads as its number.
private struct PullRow: View {
    let pull: GitHubInbox.PullRequest
    let waitingOnYou: Bool
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Image(systemName: waitingOnYou ? "eye.fill" : "arrow.triangle.pull")
                    .font(Theme.Font.label)
                    .foregroundStyle(Theme.Kind.tint(.githubInbox))
                    .frame(width: 34)
                    .accessibilityHidden(true)
                Text(pull.title ?? "Pull request #\(pull.number)")
                    .font(Theme.Font.body)
                    .foregroundStyle(pull.title == nil ? Theme.Palette.faint : Theme.Palette.bone)
                    .lineLimit(1)
            }
            HStack(spacing: 14) {
                Text("\(pull.repository) #\(pull.number)")
                    .foregroundStyle(Theme.Palette.muted)
                    .lineLimit(1)
                ChecksBadge(checks: pull.checks)
                if pull.isDraft {
                    Text("Draft").foregroundStyle(Theme.Palette.muted)
                } else if !waitingOnYou {
                    ReviewBadge(review: pull.review)
                }
                Spacer(minLength: 8)
                Text(max(0, now.timeIntervalSince(pull.updatedAt)).shortAge)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.faint)
            }
            .font(Theme.Font.caption)
            .padding(.leading, 48)
        }
    }
}

private struct ChecksBadge: View {
    let checks: GitHubInbox.Checks

    var body: some View {
        switch checks {
        case .passing: Label("Checks pass", systemImage: "checkmark.circle.fill").foregroundStyle(Theme.Palette.green)
        case .failing: Label("Checks fail", systemImage: "xmark.circle.fill").foregroundStyle(Theme.Palette.red)
        case .pending: Label("Checks running", systemImage: "circle.dashed").foregroundStyle(Theme.Palette.muted)
        case .none: EmptyView()
        }
    }
}

private struct ReviewBadge: View {
    let review: GitHubInbox.Review

    var body: some View {
        switch review {
        case .approved: Text("Approved").foregroundStyle(Theme.Palette.green)
        case .changesRequested: Text("Changes asked").foregroundStyle(Theme.Palette.red)
        case .required: Text("Needs review").foregroundStyle(Theme.Palette.muted)
        case .none: EmptyView()
        }
    }
}

/// A thread's title over its repository, why it came and its age.
private struct ThreadRow: View {
    let thread: GitHubInbox.Notification
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 14) {
                Image(systemName: symbol)
                    .font(Theme.Font.label)
                    .foregroundStyle(Theme.Kind.tint(.githubInbox))
                    .frame(width: 34)
                    .accessibilityHidden(true)
                Text(thread.title ?? withheld)
                    .font(Theme.Font.body)
                    .foregroundStyle(thread.title == nil ? Theme.Palette.faint : Theme.Palette.bone)
                    .lineLimit(1)
            }
            HStack(spacing: 14) {
                Text(thread.number.map { "\(thread.repository) #\($0)" } ?? thread.repository)
                    .foregroundStyle(Theme.Palette.muted)
                    .lineLimit(1)
                Text(reason)
                    .foregroundStyle(Theme.Palette.muted)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(max(0, now.timeIntervalSince(thread.updatedAt)).shortAge)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.faint)
            }
            .font(Theme.Font.caption)
            .padding(.leading, 48)
        }
    }

    private var symbol: String {
        switch thread.kind {
        case .pullRequest: "arrow.triangle.pull"
        case .issue: "exclamationmark.circle"
        case .release: "tag.fill"
        case .checkSuite: "gearshape.2.fill"
        case .discussion: "bubble.left.and.bubble.right.fill"
        case .commit: "smallcircle.filled.circle"
        case .other: "bell.fill"
        }
    }

    /// What a private repository's thread reads as on the TV.
    private var withheld: String {
        switch thread.kind {
        case .pullRequest: "Pull request in a private repository"
        case .issue: "Issue in a private repository"
        default: "In a private repository"
        }
    }

    private var reason: String {
        switch thread.reason {
        case "review_requested": "Review asked"
        case "mention": "Mentioned"
        case "team_mention": "Team mentioned"
        case "author": "Yours"
        case "assign": "Assigned"
        case "comment": "Commented"
        case "ci_activity": "CI"
        case "state_change": "Changed state"
        case "security_alert": "Security alert"
        case "subscribed", "manual": "Watching"
        default: thread.reason.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}
