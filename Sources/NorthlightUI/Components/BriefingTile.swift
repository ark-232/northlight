import SwiftUI
import NorthlightKit

struct BriefingTile: View {
    let briefing: Briefing?
    /// Whether the paired Mac has reported lately.
    let macReachable: Bool
    let now: Date
    @Environment(\.calendar) private var calendar
    @Environment(\.timeZone) private var zone
    @Environment(\.widgetSize) private var size

    var body: some View {
        Tile(label: "Briefing", accent: Theme.Palette.violet) {
            switch briefing {
            case .written(let text, let at)? where calendar.isDate(at, inSameDayAs: now):
                VStack(alignment: .leading, spacing: 14) {
                    Text(text)
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Palette.bone)
                        .lineLimit(size == .large ? 14 : 5)
                    Text("Written on your Mac at \(at.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)))")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.faint)
                }
            case .unavailable(let reason, let at)? where calendar.isDate(at, inSameDayAs: now):
                TilePlaceholder(text: reason)
            default:
                TilePlaceholder(text: !macReachable ? "Written on your Mac, not reachable"
                                : Briefing.isDue(after: nil, at: now, calendar: calendar) ? "Asking your Mac"
                                : "Your Mac writes the next one after five")
            }
        }
    }
}
