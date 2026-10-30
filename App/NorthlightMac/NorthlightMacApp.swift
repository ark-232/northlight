import AppKit
import NorthlightKit
import SwiftUI

/// A menu bar app: it watches this Mac's coding sessions and shows them on the
/// Apple TV, and its editor window arranges the TV's pages.
@main
struct NorthlightMacApp: App {
    @State private var feed: AgentFeed
    @State private var calendar: CalendarConnector
    @State private var github: GitHubConnector
    @State private var link = TVLink()

    init() {
        let feed = AgentFeed(), calendar = CalendarConnector(feed: feed), github = GitHubConnector(feed: feed)
        feed.connectorFrames = { [calendar.frame, github.frame].compactMap { $0 } }
        _feed = State(initialValue: feed)
        _calendar = State(initialValue: calendar)
        _github = State(initialValue: github)
    }

    var body: some Scene {
        MenuBarExtra("Northlight", systemImage: "sparkles.tv") {
            MenuView(feed: feed)
        }
        .menuBarExtraStyle(.window)

        Window("Connectors", id: "connectors") {
            ConnectorsView(calendar: calendar, github: github)
        }
        .windowResizability(.contentSize)

        Window("Northlight", id: "editor") {
            EditorView(link: link, feed: feed, calendar: calendar, github: github)
        }
        .defaultSize(width: 1500, height: 860)
        // An `-openEditor YES` launch opens it at once, for screenshots.
        .defaultLaunchBehavior(UserDefaults.standard.bool(forKey: "openEditor") ? .presented : .suppressed)
        .commands {
            CommandMenu("Layout") {
                Button("Restore Default Pages…", action: restoreDefaultPages)
                    .disabled(!link.canEdit)
            }
        }
    }

    /// Asks first, naming what goes, then sends the default pages as an edit the
    /// editor can undo.
    private func restoreDefaultPages() {
        guard let current = link.dashboard else { return }
        let alert = NSAlert()
        alert.messageText = "Restore the default pages on the Apple TV?"
        alert.informativeText = current.restoringDefaultsMessage
        alert.addButton(withTitle: "Restore")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        link.edit(.defaults, undo: NSApp.keyWindow?.undoManager)
    }
}
