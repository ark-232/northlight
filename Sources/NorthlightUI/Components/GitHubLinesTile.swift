import NorthlightKit
import SwiftUI

/// Lines of code in the viewer's five busiest repositories, all authors: the total
/// and its year as a curve, and at large size each repository's share.
struct GitHubLinesTile: View {
    /// Nil until an account is connected here or on the Mac.
    let lines: Loaded<CodeHistory>?
    let now: Date
    @Environment(\.widgetSize) private var size

    var body: some View {
        Tile(label: "Lines of code", trailing: lines?.trailing(asOf: now)) {
            if let lines {
                if size == .large {
                    LinesState(lines: lines, now: now) { history in
                        let points = history.recentTotals(52)
                        if points.isEmpty {
                            TilePlaceholder(text: "No lines to count")
                        } else {
                            VStack(alignment: .leading, spacing: 20) {
                                LinesHeadline(points: points, font: Theme.Font.hero)
                                RepositoryLines(history: history, chartHeight: 360)
                            }
                        }
                    }
                } else {
                    LinesHero(lines: lines, now: now, chartHeight: 150)
                }
            } else {
                GitHubNotConnected()
            }
        }
    }
}

/// What a GitHub widget shows before any account is connected.
struct GitHubNotConnected: View {
    var body: some View {
        Text("Connect GitHub in Settings, or sign in on the Mac")
            .font(Theme.Font.body)
            .foregroundStyle(Theme.Palette.faint)
            .lineLimit(4)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
