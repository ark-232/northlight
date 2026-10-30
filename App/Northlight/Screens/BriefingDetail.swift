import SwiftUI
import NorthlightKit
import NorthlightUI

/// The Briefing widget's detail: the day's briefing whole, and a button to have the Mac
/// write it again now.
struct BriefingDetail: View {
    let store: DashboardStore
    @Environment(\.timeZone) private var zone

    var body: some View {
        ZStack {
            SkyField()
            VStack(alignment: .leading, spacing: 40) {
                Text("Briefing")
                    .font(Theme.Font.clock)
                    .foregroundStyle(Theme.Palette.bone)
                switch store.briefing {
                case .written(let text, let at)?:
                    Text(text)
                        .font(Theme.Font.title)
                        .foregroundStyle(Theme.Palette.bone)
                        .frame(maxWidth: 1500, alignment: .leading)
                    Text("Written on your Mac \(at.formatted(Date.FormatStyle(date: .abbreviated, time: .shortened, timeZone: zone)))")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.faint)
                case .unavailable(let reason, _)?:
                    Text(reason)
                        .font(Theme.Font.title)
                        .foregroundStyle(Theme.Palette.amber)
                case nil:
                    Text("No briefing yet.")
                        .font(Theme.Font.title)
                        .foregroundStyle(Theme.Palette.muted)
                }
                // A report within the last 45 seconds is the Mac being there.
                if store.agents?.statuses(asOf: Date()) != nil {
                    Button("Write now", action: store.writeBriefingNow)
                } else {
                    Text("Your Mac is not reachable. Turn on Share with Apple TV in Northlight on the Mac.")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.muted)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
