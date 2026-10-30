import NorthlightKit
import SwiftUI

/// GitHub Actions in the viewer's five busiest repositories: at small size whether
/// every workflow's latest run passed, else the latest runs with their state,
/// workflow, repository, branch, duration and age.
struct GitHubActionsTile: View {
    /// Nil until an account is connected here or on the Mac.
    let feed: Loaded<GitHubActions>?
    let now: Date
    @Environment(\.widgetSize) private var size

    var body: some View {
        Tile(label: "Actions", trailing: feed?.trailing(asOf: now)) {
            if let feed {
                FeedBody(state: feed.state(asOf: now)) { actions in
                    if actions.runs.isEmpty {
                        TilePlaceholder(text: "No runs in your \(actions.repositories.count) busiest repos")
                    } else if size == .small {
                        ActionsOverall(actions: actions, now: now)
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            ActionsCounts(actions: actions)
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(actions.runs.prefix(size == .large ? 10 : 4), id: \.id) { run in
                                    RunRow(run: run, now: now)
                                        .transition(.push(from: .top))
                                }
                            }
                            .animation(Theme.Motion.insert, value: actions.runs.map(\.id))
                        }
                    }
                }
            } else {
                GitHubNotConnected()
            }
        }
    }
}

/// The small tile: one glyph and a few words for every workflow's latest run.
private struct ActionsOverall: View {
    let actions: GitHubActions
    let now: Date

    var body: some View {
        let failing = actions.failing, underWay = actions.underWay
        VStack(alignment: .leading, spacing: 10) {
            RunGlyph(state: failing.isEmpty ? (underWay.isEmpty ? .passed : .running) : .failed)
                .font(.system(size: 72, weight: .semibold))
            Text(failing.isEmpty ? (underWay.isEmpty ? "All passing" : "\(underWay.count) running") : "\(failing.count) failing")
                .font(Theme.Font.title)
                .foregroundStyle(failing.isEmpty ? Theme.Palette.bone : Theme.Palette.red)
                .lineLimit(1)
                .numericChange(failing.count)
            Text(detail(failing: failing, underWay: underWay))
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.muted)
                .lineLimit(2)
            if let newest = actions.runs.first {
                Text("Latest \(max(0, now.timeIntervalSince(newest.createdAt)).shortAge) ago")
                    .font(Theme.Font.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.faint)
            }
        }
    }

    private func detail(failing: [GitHubActions.Run], underWay: [GitHubActions.Run]) -> String {
        if let first = failing.first {
            let more = failing.count > 1 ? " and \(failing.count - 1) more" : ""
            return "\(first.workflow) in \(first.repository)\(more)"
        }
        let workflows = actions.latest.count, repositories = Set(actions.latest.map(\.repository)).count
        return "\(workflows) \(workflows == 1 ? "workflow" : "workflows") in \(repositories) \(repositories == 1 ? "repo" : "repos")"
    }
}

/// "1 failing · 1 running · 5 passing", over each workflow's latest run.
private struct ActionsCounts: View {
    let actions: GitHubActions

    var body: some View {
        let failing = actions.failing.count, running = actions.underWay.count
        let passing = actions.latest.filter { $0.state == .passed }.count
        HStack(spacing: 10) {
            if failing > 0 {
                Text("\(failing) failing").foregroundStyle(Theme.Palette.red)
                Text("·").foregroundStyle(Theme.Palette.faint)
            }
            if running > 0 {
                Text("\(running) running").foregroundStyle(Theme.Palette.bone)
                Text("·").foregroundStyle(Theme.Palette.faint)
            }
            Text(failing == 0 && running == 0 ? "All \(passing) passing" : "\(passing) passing")
                .foregroundStyle(failing == 0 ? Theme.Palette.green : Theme.Palette.muted)
        }
        .font(Theme.Font.body)
        .monospacedDigit()
        .lineLimit(1)
        .numericChange([failing, running, passing])
    }
}

private struct RunRow: View {
    let run: GitHubActions.Run
    let now: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            RunGlyph(state: run.state)
                .font(Theme.Font.label)
                .frame(width: 34)
            Text(run.workflow)
                .font(Theme.Font.body)
                .foregroundStyle(run.state == .failed ? Theme.Palette.red : Theme.Palette.bone)
                .lineLimit(1)
                .layoutPriority(1)
            Text(run.repository)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.muted)
                .lineLimit(1)
            if let branch = run.branch {
                Text(branch)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.faint)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .layoutPriority(-1)
            }
            Spacer(minLength: 8)
            if let duration = run.duration(asOf: now) {
                Text(duration.runLength)
                    .font(Theme.Font.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.muted)
            }
            Text(max(0, now.timeIntervalSince(run.createdAt)).shortAge)
                .font(Theme.Font.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.faint)
                .frame(width: 56, alignment: .trailing)
        }
    }
}

/// A run's state as a glyph in the status colours; a running one turns.
private struct RunGlyph: View {
    let state: GitHubActions.State
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        switch state {
        case .running:
            Image(systemName: "arrow.triangle.2.circlepath")
                .foregroundStyle(Theme.Kind.tint(.githubActions))
                .symbolEffect(.rotate, options: .repeat(.continuous), isActive: !reduceMotion)
                .accessibilityLabel("Running")
        case .queued:
            Image(systemName: "clock").foregroundStyle(Theme.Palette.muted).accessibilityLabel("Queued")
        case .passed:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.Palette.green).accessibilityLabel("Passed")
        case .failed:
            Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.Palette.red).accessibilityLabel("Failed")
        case .cancelled:
            Image(systemName: "slash.circle").foregroundStyle(Theme.Palette.muted).accessibilityLabel("Cancelled")
        case .skipped:
            Image(systemName: "minus.circle").foregroundStyle(Theme.Palette.faint).accessibilityLabel("Skipped")
        }
    }
}

extension TimeInterval {
    /// "42s", "9m 2s", "1h 5m".
    var runLength: String {
        let seconds = Int(self)
        if seconds < 60 { return "\(seconds)s" }
        if seconds < 3_600 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds / 3_600)h \(seconds % 3_600 / 60)m"
    }
}
