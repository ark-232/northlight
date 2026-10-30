import NorthlightKit
import SwiftUI

/// Where the Mac's user connects the calendars and the GitHub account the TV shows.
struct ConnectorsView: View {
    @Bindable var calendar: CalendarConnector
    let github: GitHubConnector

    var body: some View {
        Form {
            Section("Calendars") {
                if calendar.hasAccess {
                    if calendar.accounts.isEmpty {
                        Text("No calendars on this Mac. Add an account in System Settings › Internet Accounts.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(calendar.accounts) { account in
                        DisclosureGroup(account.title) {
                            ForEach(account.calendars) { item in
                                Toggle(isOn: chosen(item.id)) {
                                    Label {
                                        Text(item.title)
                                    } icon: {
                                        Image(systemName: "circle.fill").foregroundStyle(Color(nsColor: item.color))
                                    }
                                }
                            }
                        }
                    }
                    status(calendar.status)
                } else if calendar.access == .notDetermined {
                    Text("Northlight reads the calendars you choose here and shows their next two weeks on the TV.")
                    Button("Allow Calendar Access") { Task { await calendar.grant() } }
                } else {
                    Text("Calendar access is off for Northlight.")
                    Button("Open Privacy Settings", action: calendar.openPrivacySettings)
                }
            }

            Section("GitHub") {
                switch github.step {
                case .signedOut, .failed:
                    Button("Sign In with GitHub", action: github.signIn)
                    if case .failed(let reason) = github.step {
                        Text(reason).foregroundStyle(.orange)
                    }
                case .starting:
                    ProgressView("Asking GitHub for a code")
                case .showing(let code):
                    Text("Enter this code at \(code.verificationURI.host() ?? "")\(code.verificationURI.path()). It is on your clipboard.")
                        .fixedSize(horizontal: false, vertical: true)
                    Text(code.userCode)
                        .font(.title.monospaced())
                        .textSelection(.enabled)
                    HStack {
                        Button("Copy and Open GitHub") { github.copyAndOpen(code) }
                        Button("Cancel", action: github.cancelSignIn)
                    }
                case .signedIn:
                    status(github.status.isEmpty ? "Signed in" : github.status)
                    Text("Repositories and commits whose names contain a blocked fragment show as Private.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Sign Out", action: github.signOut)
                }
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 380, minHeight: 420)
    }

    private func chosen(_ id: String) -> Binding<Bool> {
        Binding {
            calendar.chosen.contains(id)
        } set: { on in
            if on { calendar.chosen.insert(id) } else { calendar.chosen.remove(id) }
        }
    }

    @ViewBuilder private func status(_ line: String) -> some View {
        if !line.isEmpty {
            Text(line).foregroundStyle(.secondary)
        }
    }
}
