import SwiftUI
import NorthlightKit
import NorthlightUI

/// Connects iCloud calendars with an Apple ID and an app-specific password, which iCloud
/// requires of calendar apps, and chooses which of them the Agenda shows.
struct ICloudCalendars: View {
    @Binding var account: ICloudAccount?
    @State private var appleID = ""
    @State private var password = ""
    /// Every event calendar in the account, once looked up.
    @State private var available: [CalDAV.Calendar] = []
    @State private var finding = false
    @State private var failure: String?

    private static let http = HTTP(userAgent: "Northlight/1.0")

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("ICLOUD CALENDARS")
                .font(Theme.Font.label)
                .tracking(1.6)
                .foregroundStyle(Theme.Palette.muted)
            if let account {
                Text(account.appleID)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Palette.bone)
                if available.isEmpty {
                    Text(account.calendars.isEmpty ? "No calendars chosen" : account.calendars.map(\.name).joined(separator: ", "))
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Palette.muted)
                    Button("Choose calendars") { find(appleID: account.appleID, password: account.password) }
                        .disabled(finding)
                } else {
                    ForEach(available, id: \.self) { calendar in
                        Toggle(calendar.name, isOn: Binding(
                            get: { account.calendars.contains(calendar) },
                            set: { on in
                                save(ICloudAccount(appleID: account.appleID, password: account.password,
                                                   calendars: available.filter { $0 == calendar ? on : account.calendars.contains($0) }))
                            }
                        ))
                        .frame(maxWidth: 1100)
                    }
                }
                Button("Disconnect iCloud") {
                    available = []
                    save(nil)
                }
            } else {
                Text("Not connected")
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Palette.bone)
                TextField("Apple ID", text: $appleID)
                    .textContentType(.username)
                    .frame(maxWidth: 1100)
                SecureField("App-specific password", text: $password)
                    .frame(maxWidth: 1100)
                Text("Make an app-specific password at account.apple.com, under Sign-In and Security.")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.muted)
                if !appleID.isEmpty, !password.isEmpty {
                    Button(finding ? "Connecting" : "Connect") { find(appleID: appleID, password: password) }
                        .disabled(finding)
                }
            }
            if let failure {
                Text(failure)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.amber)
            }
        }
    }

    /// Looks the account's calendars up. A first connection shows all of them; choosing
    /// again keeps what was chosen.
    private func find(appleID: String, password: String) {
        finding = true
        failure = nil
        Task {
            defer { finding = false }
            do {
                let calendars = try await Self.http.icloudCalendars(appleID: appleID, password: password)
                available = calendars
                if save(ICloudAccount(appleID: appleID, password: password,
                                      calendars: account.map { chosen in calendars.filter(chosen.calendars.contains) } ?? calendars)) {
                    self.password = ""
                }
            } catch FeedError.refused {
                failure = "iCloud did not accept that Apple ID and app-specific password."
            } catch {
                failure = "iCloud could not be reached: \(DashboardStore.describe(error))."
            }
        }
    }

    @discardableResult
    private func save(_ next: ICloudAccount?) -> Bool {
        do {
            if let next {
                try Keychain.save(String(decoding: try JSONEncoder().encode(next), as: UTF8.self), as: .icloud)
            } else {
                Keychain.delete(.icloud)
            }
            account = next
            return true
        } catch let error as Keychain.Failure {
            failure = "The keychain refused the account (status \(error.status))."
        } catch {
            failure = "The account could not be saved."
        }
        return false
    }
}
