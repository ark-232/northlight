import SwiftUI
import NorthlightKit
import NorthlightUI

/// Where the dashboard is and how it reads. The first run stays here until a place is
/// set; after that, the header's gear opens it.
struct SettingsView: View {
    @Binding var settings: Settings
    @Binding var calendarURL: URL?
    @Binding var githubToken: String?
    @Binding var icloud: ICloudAccount?
    /// The layout on screen; nil on the first run, which has none yet.
    var dashboard: Binding<Dashboard>? = nil
    /// Nil on the first run, which has no dashboard to return to.
    var onDone: (() -> Void)?

    @State private var locator = PlaceLocator()
    @State private var search = PlaceSearch()
    @State private var showingAbout = false
    @AppStorage("speedTestConsent") private var speedTestConsent = false
    @AppStorage("speedTestsAutomatic") private var speedTestsAutomatic = false
    @State private var calendarEntry = ""
    @State private var calendarError: String?
    @State private var confirmingRestore = false

    var body: some View {
        ZStack {
            SkyField()

            ScrollView {
                VStack(alignment: .leading, spacing: 56) {
                    Text("Northlight")
                        .font(Theme.Font.clock)
                        .foregroundStyle(Theme.Palette.bone)

                    VStack(alignment: .leading, spacing: 20) {
                        Text("PLACE")
                            .font(Theme.Font.label)
                            .tracking(1.6)
                            .foregroundStyle(Theme.Palette.muted)
                        Text(settings.place?.name ?? "Not set")
                            .font(Theme.Font.title)
                            .foregroundStyle(Theme.Palette.bone)
                        Button("Use this Apple TV's location") {
                            Task {
                                if let place = await locator.locate() { settings.place = place }
                            }
                        }
                        .disabled(locator.status == .locating)
                        switch locator.status {
                        case .idle:
                            EmptyView()
                        case .locating:
                            Text("Locating…")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.muted)
                        case .failed(let message):
                            Text(message)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.amber)
                        }
                        TextField("Search for a place", text: $search.query)
                            .frame(maxWidth: 1100)
                        ForEach(search.results, id: \.self) { result in
                            Button {
                                Task {
                                    guard let place = await search.place(for: result) else { return }
                                    settings.place = place
                                    search.query = ""
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.title)
                                    Text(result.subtitle)
                                        .font(Theme.Font.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        if let failure = search.failure {
                            Text(failure)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.amber)
                        }
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        Text("UNITS")
                            .font(Theme.Font.label)
                            .tracking(1.6)
                            .foregroundStyle(Theme.Palette.muted)
                        Picker("Units", selection: $settings.units) {
                            Text("Automatic").tag(Units?.none)
                            Text("Metric").tag(Units?.some(.metric))
                            Text("Imperial").tag(Units?.some(.imperial))
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 900)
                    }

                    VStack(alignment: .leading, spacing: 20) {
                        Text("CALENDAR")
                            .font(Theme.Font.label)
                            .tracking(1.6)
                            .foregroundStyle(Theme.Palette.muted)
                        // The address is a bearer secret, so only its host and length show.
                        Text(calendarURL.map { "\($0.host() ?? "Calendar"), \($0.absoluteString.count) characters" } ?? "Not set")
                            .font(Theme.Font.title)
                            .foregroundStyle(Theme.Palette.bone)
                        SecureField("Paste a calendar's .ics address", text: $calendarEntry)
                            .onSubmit(saveCalendar)
                            .frame(maxWidth: 1100)
                        // Back closes the keyboard without submitting, so saving is
                        // also a button of its own.
                        if !calendarEntry.isEmpty {
                            Button("Save address", action: saveCalendar)
                        }
                        if calendarURL != nil {
                            Button("Remove calendar") {
                                Keychain.delete(.calendarURL)
                                calendarURL = nil
                            }
                        }
                        if let calendarError {
                            Text(calendarError)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.amber)
                        }
                    }

                    ICloudCalendars(account: $icloud)

                    GitHubSignIn(token: $githubToken)

                    VStack(alignment: .leading, spacing: 20) {
                        Text("SPEED TESTS")
                            .font(Theme.Font.label)
                            .tracking(1.6)
                            .foregroundStyle(Theme.Palette.muted)
                        // Agreeing happens at the first test, where what M-Lab publishes is said.
                        Text(speedTestConsent ? "Allowed on M-Lab" : "Not allowed")
                            .font(Theme.Font.title)
                            .foregroundStyle(Theme.Palette.bone)
                        if speedTestConsent {
                            Toggle("Also test on its own, about twice a day", isOn: $speedTestsAutomatic)
                                .frame(maxWidth: 1100)
                            Text("Each test moves up to about 300 MB, and only on a connection that is not metered.")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.muted)
                            Button("Stop allowing speed tests") {
                                speedTestConsent = false
                                speedTestsAutomatic = false
                            }
                        }
                    }

                    if let dashboard {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("PAGES")
                                .font(Theme.Font.label)
                                .tracking(1.6)
                                .foregroundStyle(Theme.Palette.muted)
                            Text(dashboard.wrappedValue.pages.map(\.name).formatted(.list(type: .and)))
                                .font(Theme.Font.title)
                                .foregroundStyle(Theme.Palette.bone)
                                .lineLimit(2)
                            Button("Restore default pages") { confirmingRestore = true }
                        }
                        .confirmationDialog("Restore the default pages?", isPresented: $confirmingRestore, titleVisibility: .visible) {
                            Button("Restore", role: .destructive) { dashboard.wrappedValue = .defaults }
                        } message: {
                            Text(dashboard.wrappedValue.restoringDefaultsMessage)
                        }
                    }

                    HStack(spacing: 40) {
                        Button("About Northlight") { showingAbout = true }
                        if let onDone, settings.place != nil {
                            Button("Done", action: onDone)
                        }
                    }
                }
                .padding(80)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .fullScreenCover(isPresented: $showingAbout) { About() }
    }

    private func saveCalendar() {
        let entry = calendarEntry
        calendarEntry = ""
        guard let url = calendarFeedURL(from: entry) else {
            calendarError = "That is not a web address."
            return
        }
        do {
            try Keychain.save(url.absoluteString, as: .calendarURL)
            calendarURL = url
            calendarError = nil
        } catch {
            calendarError = "The keychain refused the address (status \(error.status))."
        }
    }
}
