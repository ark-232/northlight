import SwiftUI
import NorthlightKit
import NorthlightUI

/// Connects a GitHub account by device flow: this shows a code, the owner types it
/// at github.com/login/device on a phone, and this polls until GitHub approves.
struct GitHubSignIn: View {
    @Binding var token: String?
    @State private var step = Step.idle

    private static let http = HTTP(userAgent: "Northlight/1.0")

    private enum Step: Equatable {
        case idle, starting
        case showing(GitHubDeviceFlow.Code)
        case failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("GITHUB")
                .font(Theme.Font.label)
                .tracking(1.6)
                .foregroundStyle(Theme.Palette.muted)
            if token != nil {
                Text("Connected")
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Palette.bone)
                Button("Disconnect GitHub") {
                    Keychain.delete(.githubToken)
                    token = nil
                }
            } else if case .showing(let code) = step {
                Text("On your phone, open \(code.verificationURI.host() ?? "")\(code.verificationURI.path()) and enter")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.muted)
                Text(code.userCode)
                    .font(Theme.Font.promoted)
                    .monospaced()
                    .foregroundStyle(Theme.Palette.bone)
                Button("Cancel") { step = .idle }
            } else {
                Text("Not connected")
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Palette.bone)
                Button("Connect GitHub") { step = .starting }
                    .disabled(step == .starting)
                if case .failed(let reason) = step {
                    Text(reason)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.amber)
                }
            }
        }
        .task(id: signingIn) { await signIn() }
    }

    private var signingIn: Bool {
        switch step {
        case .starting, .showing: true
        case .idle, .failed: false
        }
    }

    /// Runs from Connect until a token or a failure; Cancel returns to idle, which ends it.
    private func signIn() async {
        guard step == .starting else { return }
        do {
            let value = try await GitHubDeviceFlow.signIn(http: Self.http) { @MainActor code in step = .showing(code) }
            do {
                try Keychain.save(value, as: .githubToken)
                token = value
                step = .idle
            } catch {
                step = .failed("The keychain refused the token (status \(error.status)).")
            }
        } catch is CancellationError {
        } catch {
            step = .failed(DashboardStore.describe(error))
        }
    }
}
