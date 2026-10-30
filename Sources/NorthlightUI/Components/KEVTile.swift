import NorthlightKit
import SwiftUI

/// How many vulnerabilities CISA has seen exploited this week, and the latest three.
struct KEVTile: View {
    let feed: Loaded<KEVCatalog>
    let now: Date
    @Environment(\.widgetKind) private var kind

    /// The catalog dates days, not instants, so they print as UTC days.
    /// A catalog day is a UTC date. Formatted to a string, since Text's format applies
    /// the place's zone over the style's, which puts a day before.
    private static let day = Date.FormatStyle(timeZone: TimeZone(identifier: "UTC")!).month(.abbreviated).day()

    var body: some View {
        Tile(label: "Known exploited", trailing: feed.trailing(asOf: now)) {
            FeedBody(state: feed.state(asOf: now)) { catalog in
                let week = catalog.addedThisWeek(at: now)
                VStack(alignment: .leading, spacing: 14) {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        Text("+\(week)")
                            .font(Theme.Font.tileValue)
                            .foregroundStyle(week > 0 ? kind.map(Theme.Kind.tint) ?? Theme.Palette.bone : Theme.Palette.muted)
                            .numericChange(week)
                        Text("this week")
                            .font(Theme.Font.body)
                            .foregroundStyle(Theme.Palette.muted)
                        Spacer(minLength: 12)
                        Text("\(catalog.count.formatted()) in the catalog")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.faint)
                    }
                    .lineLimit(1)
                    ForEach(catalog.recent.prefix(3)) { entry in
                        HStack(alignment: .firstTextBaseline, spacing: 18) {
                            Text(entry.cve)
                                .font(Theme.Font.caption)
                                .monospacedDigit()
                                .foregroundStyle(Theme.Palette.bone)
                                .fixedSize()
                            Text("\(entry.vendor) \(entry.product)")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.muted)
                                .lineLimit(1)
                            Spacer(minLength: 8)
                            Text(entry.added.formatted(Self.day))
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.faint)
                                .fixedSize()
                        }
                    }
                }
            }
        }
    }
}
