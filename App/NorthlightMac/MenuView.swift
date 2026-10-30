import NorthlightKit
import SwiftUI

struct MenuView: View {
    @Bindable var feed: AgentFeed
    @Environment(\.openWindow) private var openWindow
    @State private var entry = ""

    private var tvLine: String {
        switch feed.tv {
        case .looking: "Looking for an Apple TV running Northlight"
        case .found(let name): "Found \(name), not connected"
        case .showing(let name): "Showing on \(name)"
        case .unpaired: "This build has no pairing key yet"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Northlight")
                .font(.headline)
            Toggle("Share with Apple TV", isOn: $feed.sharing)
            Text("Your coding sessions, redacted, and the morning briefing, written on this Mac.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if feed.sharing {
                Text(tvLine)
                    .foregroundStyle(.secondary)
            }

            Divider()

            if feed.folder == nil {
                Text("Northlight reads Claude Code's transcripts to see what it is doing.")
                    .fixedSize(horizontal: false, vertical: true)
                Button("Choose ~/.claude/projects…", action: feed.chooseFolder)
            } else if feed.statuses.isEmpty {
                Text("No session running")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(feed.statuses) { status in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.redacted ? "\(status.agent), hidden" : "\(status.agent) · \(status.project ?? "")")
                        Text(status.verb)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Divider()

            usageSection

            Divider()

            Text("Show only as busy when a session's name or paths contain:")
                .fixedSize(horizontal: false, vertical: true)
            ForEach(feed.blocked, id: \.self) { fragment in
                HStack {
                    Text(fragment)
                    Spacer()
                    Button("Remove", systemImage: "minus.circle") { feed.blocked.removeAll { $0 == fragment } }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                }
            }
            HStack {
                TextField("Folder or name", text: $entry)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(entry.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            Divider()

            Button("Open Editor") {
                openWindow(id: "editor")
                NSApp.activate()
            }
            Button("Calendars and GitHub…") {
                openWindow(id: "connectors")
                NSApp.activate()
            }

            Divider()

            Button("Quit Northlight") { NSApplication.shared.terminate(nil) }
        }
        .padding(16)
        .frame(width: 360)
    }

    /// The account's usage once the wrapper has written it; until then, how to set it up.
    @ViewBuilder private var usageSection: some View {
        if let usage = feed.usage {
            let now = Date()
            let current = usage.current(asOf: now)
            Text("Claude usage")
            if current.isEmpty {
                Text("No usage window open")
                    .foregroundStyle(.secondary)
            }
            if let fiveHour = current.fiveHour {
                Text(fiveHour.line("5 h", now: now, timeZone: .current))
            }
            if let sevenDay = current.sevenDay {
                Text(sevenDay.line("7 d", now: now, timeZone: .current))
            }
            Text("as of \(usage.observedAt.formatted(date: .omitted, time: .shortened))")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("To show Claude usage, copy the script to ~/.claude, then put it in front of your status line in ~/.claude/settings.json:")
                .fixedSize(horizontal: false, vertical: true)
            Group {
                Text("cp \"\(AgentFeed.usageScript?.path ?? "northlight-statusline.sh")\" ~/.claude/northlight-statusline.sh")
                Text(#""statusLine": {"type": "command", "command": "sh ~/.claude/northlight-statusline.sh claude-powerline --style=powerline"}"#)
            }
            .font(.caption.monospaced())
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            Text("Replace claude-powerline --style=powerline with your own status line command, or leave it off.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let script = AgentFeed.usageScript {
                Button("Reveal Script") { NSWorkspace.shared.activateFileViewerSelecting([script]) }
            }
        }
    }

    private func add() {
        let fragment = entry.trimmingCharacters(in: .whitespaces)
        entry = ""
        guard !fragment.isEmpty, !feed.blocked.contains(fragment) else { return }
        feed.blocked.append(fragment)
    }
}
