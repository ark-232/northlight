import SwiftUI
import NorthlightKit

struct AuroraTile: View {
    let feed: Loaded<Aurora>
    let now: Date
    @Environment(\.widgetSize) private var size

    /// Kp ramp: quiet reads cool and recedes, storm reads warm and advances.
    private func color(for kp: Double) -> Color {
        switch kp {
        case ..<3: return Theme.Palette.muted
        case ..<5: return Theme.Palette.green
        case ..<6: return Theme.Palette.amber
        default: return Theme.Palette.red
        }
    }

    private func value(_ aurora: Aurora) -> some View {
        Text("Kp \(aurora.kp, specifier: "%.1f")")
            .font(Theme.Font.tileValue)
            .foregroundStyle(color(for: aurora.kp))
            .numericChange(aurora.kp)
    }

    private func activity(_ aurora: Aurora) -> some View {
        Text(aurora.activityLabel.uppercased())
            .font(Theme.Font.caption)
            .tracking(1.2)
            .foregroundStyle(Theme.Palette.muted)
            .lineLimit(1)
            .accessibilityLabel(aurora.activityLabel)
    }

    var body: some View {
        Tile(label: "Aurora", accent: Theme.Palette.green, trailing: feed.trailing(asOf: now)) {
            FeedBody(state: feed.state(asOf: now)) { aurora in
                VStack(alignment: .leading, spacing: 10) {
                    // The activity goes under the value when the two will not share a line.
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .firstTextBaseline, spacing: 14) { value(aurora); activity(aurora) }
                        VStack(alignment: .leading, spacing: 4) { value(aurora); activity(aurora) }
                    }
                    if let probability = aurora.localProbability {
                        Text("\(probability)% overhead")
                            .font(Theme.Font.body)
                            .foregroundStyle(probability >= 30 ? Theme.Palette.green : Theme.Palette.muted)
                            .numericChange(probability)
                            .lineLimit(1)
                    }
                    if size == .medium {
                        // Kp 1 to 9, lit up to the current value.
                        HStack(spacing: 8) {
                            ForEach(1...9, id: \.self) { step in
                                Capsule()
                                    .fill(step <= Int(aurora.kp.rounded(.up)) ? color(for: Double(step)) : Theme.Palette.hairline)
                                    .frame(height: 14)
                            }
                        }
                        .padding(.top, 12)
                    }
                }
            }
        }
    }
}

struct QuakeTile: View {
    let feed: Loaded<[Quake]>
    let minMagnitude: Double
    let now: Date
    @Environment(\.widgetSize) private var size
    @Environment(\.locale) private var locale

    private func color(for magnitude: Double) -> Color {
        switch magnitude {
        case ..<3: return Theme.Palette.muted
        case ..<4: return Theme.Palette.cyan
        case ..<5: return Theme.Palette.amber
        default: return Theme.Palette.red
        }
    }

    var body: some View {
        Tile(label: "Seismic", accent: Theme.Palette.amber, trailing: feed.trailing(asOf: now)) {
            FeedBody(state: feed.state(asOf: now)) { fetched in
                // One fetch serves every seismic widget, from the lowest threshold.
                let quakes = fetched.filter { $0.magnitude >= minMagnitude }
                if quakes.isEmpty {
                    TilePlaceholder(text: "Nothing above M\(minMagnitude.formatted(.number.precision(.fractionLength(1)).locale(locale))) this week")
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(quakes.prefix(size == .large ? 13 : 5)) { quake in
                            HStack(spacing: 18) {
                                Text(String(format: "%.1f", quake.magnitude))
                                    .font(.system(size: 25, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.Palette.background)
                                    .frame(width: 68, height: 38)
                                    .background(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .fill(color(for: quake.magnitude))
                                    )
                                Text(shortPlace(quake.place))
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Palette.bone)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                Text(now.timeIntervalSince(quake.time).shortAge)
                                    .font(Theme.Font.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.Palette.faint)
                            }
                        }
                    }
                }
            }
        }
    }

    /// USGS place strings read "12 km SW of Grindavík, Iceland". Inside a
    /// 500 km circle the trailing region is the same for nearly every quake.
    private func shortPlace(_ place: String) -> String {
        guard let comma = place.range(of: ", ", options: .backwards) else { return place }
        return String(place[..<comma.lowerBound])
    }
}
