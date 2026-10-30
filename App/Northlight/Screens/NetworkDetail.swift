import SwiftUI
import NorthlightKit
import NorthlightUI

/// The Network widget's detail: the path, six hours of round trips and the speed tester,
/// whose button asks first, since M-Lab publishes every tester's IP address.
struct NetworkDetail: View {
    let store: DashboardStore
    @AppStorage("speedTestConsent") private var consented = false
    @AppStorage("speedTestsAutomatic") private var automatic = false
    @AppStorage("speedTestNext") private var automaticNext = 0.0
    @State private var asking = false

    var body: some View {
        ZStack {
            SkyField()
            TimelineView(.everyMinute) { context in
                NetworkScreen(path: store.path, latency: store.latency, tests: store.speedTests,
                              throughput: store.throughput, running: store.speedTestRunning, error: store.speedTestError,
                              automatic: automatic ? (SpeedSchedule.count(in: store.speedTests.map(\.date), asOf: context.date),
                                                      automaticNext > context.date.timeIntervalSince1970
                                                          ? Date(timeIntervalSince1970: automaticNext) : nil) : nil,
                              now: context.date) {
                    Button(store.speedTestRunning ? "Testing" : "Run speed test") {
                        if consented { store.runSpeedTest() } else { asking = true }
                    }
                    .disabled(store.speedTestRunning)
                }
            }
        }
        .fullScreenCover(isPresented: $asking) {
            SpeedTestConsent {
                consented = true
                asking = false
                store.runSpeedTest()
            } decline: {
                asking = false
            }
        }
    }
}

/// What a speed test sends and who publishes it, asked once before the first test.
struct SpeedTestConsent: View {
    let agree: () -> Void
    let decline: () -> Void

    var body: some View {
        ZStack {
            SkyField()
            VStack(alignment: .leading, spacing: 32) {
                Text("Run a speed test?")
                    .font(Theme.Font.clock)
                    .foregroundStyle(Theme.Palette.bone)
                Text("Speed tests run on M-Lab, an open platform that measures the internet. M-Lab keeps every test and publishes it as open data anyone may use: your public IP address, the date and time, and the results. Northlight sends nothing else about you or this Apple TV.")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.bone)
                    .frame(maxWidth: 1400, alignment: .leading)
                Text("You must be 16 or older to run a test.")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.bone)
                VStack(alignment: .leading, spacing: 8) {
                    Text("M-Lab privacy policy: measurementlab.net/privacy")
                    Text("M-Lab acceptable use policy: measurementlab.net/aup")
                }
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.muted)
                HStack(spacing: 40) {
                    Button("Not now", action: decline)
                    Button("Agree and run", action: agree)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
