import NorthlightKit
import SwiftUI

/// Every coding session the Mac reports: the most active one in full, the rest as
/// one line each, idle ones included, and a count of any that do not fit.
struct AgentsTile: View {
    /// Nil until the Mac is reachable.
    let statuses: [AgentStatus]?
    let usage: UsageReading?
    let now: Date
    @Environment(\.widgetSize) private var size

    /// Waiting on you first, then working, then idle; newest first within each.
    private func ordered(_ statuses: [AgentStatus]) -> [AgentStatus] {
        func rank(_ status: AgentStatus) -> Int {
            switch status.activity {
            case .waiting: 0
            case .thinking, .composing, .tool: 1
            case .idle: 2
            }
        }
        return statuses.sorted { (rank($0), $1.updatedAt) < (rank($1), $0.updatedAt) }
    }

    var body: some View {
        Tile(label: "Agents", accent: Theme.Palette.amber) {
            sessions
            if statuses != nil || usage != nil {
                Spacer(minLength: 0)
                UsageBlock(usage: usage, now: now)
            }
        }
    }

    @ViewBuilder private var sessions: some View {
        if let statuses {
            if statuses.isEmpty {
                TilePlaceholder(text: "No Claude Code sessions in the last 12 hours")
            } else {
                let sessions = ordered(statuses)
                let full = size == .large ? 2 : 1
                // The usage row takes one line's room.
                let lines = size == .large ? 4 : 1
                let shown = sessions.prefix(full + lines)
                VStack(alignment: .leading, spacing: 18) {
                    ForEach(shown.prefix(full)) { status in
                        AgentRow(status: status, detailed: size == .large)
                    }
                    ForEach(shown.dropFirst(full)) { status in
                        AgentLine(status: status)
                    }
                    if sessions.count > shown.count {
                        Text("+\(sessions.count - shown.count) more")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.faint)
                    }
                }
            }
        } else {
            TilePlaceholder(text: "Waiting for your Mac")
        }
    }
}

/// What a session is doing, as a symbol that moves while the turn runs.
private struct ActivityGlyph: View {
    let activity: AgentStatus.Activity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var symbol: String {
        switch activity {
        case .thinking: "brain"
        case .composing: "text.cursor"
        case .tool: "hammer.fill"
        case .waiting: "hand.raised.fill"
        case .idle: "moon.zzz.fill"
        }
    }

    private var color: Color {
        switch activity {
        case .thinking, .composing, .tool: Theme.Kind.tint(.agents)
        case .waiting: Theme.Palette.amber
        case .idle: Theme.Palette.faint
        }
    }

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(color)
            .symbolEffect(.pulse, isActive: !reduceMotion && activity != .idle)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: 40)
            .accessibilityHidden(true)
    }
}

/// One session on one line: what it is doing, where, and for how long.
private struct AgentLine: View {
    let status: AgentStatus

    var body: some View {
        HStack(spacing: 12) {
            ActivityGlyph(activity: status.activity)
                .font(Theme.Font.caption)
            Text(status.project ?? status.agent)
                .foregroundStyle(Theme.Palette.bone)
            Text(status.activity == .idle ? "Idle" : status.verb)
                .foregroundStyle(Theme.Palette.muted)
            Spacer(minLength: 12)
            if let elapsed = status.elapsed, status.activity != .idle {
                Text(elapsed.shortAge)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.faint)
            }
        }
        .font(Theme.Font.caption)
        .lineLimit(1)
    }
}

private struct AgentRow: View {
    let status: AgentStatus
    let detailed: Bool

    private var place: String? {
        guard let project = status.project else { return nil }
        return status.branch.map { "\(project) · \($0)" } ?? project
    }

    private var measures: String {
        var parts: [String] = []
        if let elapsed = status.elapsed {
            parts.append(Duration.seconds(elapsed).formatted(.units(allowed: [.hours, .minutes, .seconds], width: .narrow)))
        }
        if let tokens = status.outputTokens {
            parts.append("\(tokens.formatted(.number.notation(.compactName))) tokens")
        }
        if status.subagents > 0 {
            parts.append("+\(status.subagents) agent\(status.subagents == 1 ? "" : "s")")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                ActivityGlyph(activity: status.activity)
                    .font(Theme.Font.label)
                Text(status.agent)
                    .font(Theme.Font.label)
                    .foregroundStyle(Theme.Palette.muted)
                if let place {
                    Text(place)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.faint)
                        .lineLimit(1)
                }
                Spacer(minLength: 12)
                Text(measures)
                    .font(Theme.Font.caption)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.faint)
                    .lineLimit(1)
            }
            Text(status.verb)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.bone)
                .lineLimit(1)
            if detailed, let thinking = status.thinking {
                Text(thinking)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.muted)
                    .lineLimit(3)
            }
        }
    }
}
