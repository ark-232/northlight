import NorthlightKit
import SwiftUI

/// Whether GitHub and Claude are up, each as a status colour and a word, and at
/// medium size the incident open now.
struct ServiceStatusTile: View {
    let feed: Loaded<[ServiceStatus]>
    let now: Date
    @Environment(\.widgetSize) private var size

    var body: some View {
        Tile(label: "Status", trailing: feed.trailing(asOf: now)) {
            FeedBody(state: feed.state(asOf: now)) { statuses in
                VStack(alignment: .leading, spacing: size == .small ? 20 : 24) {
                    ForEach(statuses) { status in
                        row(status)
                    }
                }
            }
        }
    }

    private func row(_ status: ServiceStatus) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Circle()
                .fill(color(status.indicator))
                .frame(width: 18, height: 18)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(status.service)
                        .font(Theme.Font.title)
                        .foregroundStyle(Theme.Palette.bone)
                    if size == .medium {
                        Text(status.summary)
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.muted)
                    }
                }
                .lineLimit(1)
                if size == .small {
                    Text(word(status.indicator))
                        .font(Theme.Font.caption)
                        .foregroundStyle(color(status.indicator))
                } else if let incident = status.incident {
                    Text(incident)
                        .font(Theme.Font.caption)
                        .foregroundStyle(color(status.indicator))
                        .lineLimit(1)
                }
            }
        }
        .animation(Theme.Motion.data, value: status)
    }

    private func color(_ indicator: ServiceStatus.Indicator) -> Color {
        switch indicator {
        case .none: Theme.Palette.green
        case .maintenance: Theme.Palette.cyan
        case .minor: Theme.Palette.amber
        case .major, .critical: Theme.Palette.red
        case .unknown: Theme.Palette.faint
        }
    }

    private func word(_ indicator: ServiceStatus.Indicator) -> String {
        switch indicator {
        case .none: "Operational"
        case .maintenance: "Maintenance"
        case .minor: "Minor issues"
        case .major: "Major outage"
        case .critical: "Critical outage"
        case .unknown: "Unknown"
        }
    }
}
