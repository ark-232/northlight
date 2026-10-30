import NorthlightKit
import SwiftUI

/// A countdown to the next orbital launch, what is flying and from where, and at
/// large size the launches after it.
struct LaunchesTile: View {
    let feed: Loaded<[Launch]>
    let now: Date
    @Environment(\.widgetSize) private var size
    @Environment(\.calendar) private var calendar

    var body: some View {
        Tile(label: "Launches", trailing: feed.trailing(asOf: now)) {
            FeedBody(state: feed.state(asOf: now)) { launches in
                let upcoming = Launch.upcoming(launches, at: now)
                if let next = upcoming.first {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .firstTextBaseline) {
                            Countdown(launch: next, now: now)
                            Spacer(minLength: 16)
                            StatusChip(status: next.status)
                        }
                        Text(next.mission)
                            .font(Theme.Font.title)
                            .foregroundStyle(Theme.Palette.bone)
                            .lineLimit(1)
                        Text([next.rocket, next.provider, next.pad].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.muted)
                            .lineLimit(1)
                        if size == .large {
                            VStack(alignment: .leading, spacing: 16) {
                                ForEach(upcoming.dropFirst().prefix(5)) { launch in
                                    row(launch)
                                }
                            }
                            .padding(.top, 20)
                        }
                    }
                } else {
                    TilePlaceholder(text: "Nothing on the schedule")
                }
            }
        }
    }

    private func row(_ launch: Launch) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 20) {
            Text(launch.net, format: launch.isExact
                 ? Date.FormatStyle(timeZone: calendar.timeZone).weekday(.abbreviated).hour().minute()
                 : Date.FormatStyle(timeZone: calendar.timeZone).month(.abbreviated).day())
                .font(Theme.Font.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.faint)
                .frame(width: 170, alignment: .leading)
            Text(launch.mission)
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.bone)
                .lineLimit(1)
            Spacer(minLength: 12)
            Text(launch.rocket)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.muted)
                .lineLimit(1)
        }
    }
}

/// T− to the next launch: by the second within the hour, by the minute further
/// out, and as a date when the launch is only known to the day.
private struct Countdown: View {
    let launch: Launch
    let now: Date
    @Environment(\.widgetSize) private var size
    @Environment(\.calendar) private var calendar

    var body: some View {
        Group {
            if launch.isExact || launch.precision == "HR" {
                let close = abs(launch.net.timeIntervalSince(now)) < 3_700
                TimelineView(.periodic(from: now, by: close ? 1 : 60)) { context in
                    let remaining = launch.net.timeIntervalSince(context.date)
                    Text((launch.isExact ? "" : "≈ ") + Launch.countdown(remaining))
                        .numericChange(Int(remaining))
                }
            } else {
                Text("NET \(launch.net, format: Date.FormatStyle(timeZone: calendar.timeZone).month(.abbreviated).day())")
            }
        }
        .font(size == .large ? Theme.Font.hero : Theme.Font.promoted)
        .foregroundStyle(Theme.Palette.bone)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }
}

private struct StatusChip: View {
    let status: String

    var body: some View {
        let color: Color = switch status {
        case "Go": Theme.Palette.green
        case "Hold": Theme.Palette.amber
        case "In Flight": Theme.Palette.cyan
        default: Theme.Palette.muted
        }
        Text(status)
            .font(Theme.Font.label)
            .foregroundStyle(color)
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .background(Capsule().fill(Theme.Palette.surface))
    }
}
