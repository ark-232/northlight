import NorthlightKit
import SwiftUI

extension UsageReading.Level {
    /// Bone while there is room, so amber and red mean only "running out".
    var color: Color {
        switch self {
        case .normal: Theme.Palette.bone
        case .warning: Theme.Palette.amber
        case .critical: Theme.Palette.red
        }
    }
}

/// A usage window as a ring filling clockwise from the top.
public struct UsageRing: View {
    let percentage: Double
    let diameter: CGFloat
    let lineWidth: CGFloat

    public init(percentage: Double, diameter: CGFloat, lineWidth: CGFloat) {
        self.percentage = percentage
        self.diameter = diameter
        self.lineWidth = lineWidth
    }

    public var body: some View {
        ZStack {
            Circle().stroke(Theme.Palette.surface, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(percentage, 0), 100) / 100)
                .stroke(UsageReading.Level(percentage).color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: diameter, height: diameter)
        .animation(Theme.Motion.data, value: percentage)
        .accessibilityHidden(true)
    }
}

/// The Agents tile's usage: two bars at medium, two rings at large, each window shown
/// only until it resets, and when the figures were read.
struct UsageBlock: View {
    let usage: UsageReading?
    let now: Date
    @Environment(\.widgetSize) private var size
    @Environment(\.timeZone) private var zone
    @Environment(\.locale) private var locale

    var body: some View {
        let current = usage?.current(asOf: now)
        if let usage, let current, !current.isEmpty {
            let windows = [("5 h", current.fiveHour), ("7 d", current.sevenDay)].compactMap { name, window in
                window.map { (name, $0) }
            }
            let asOf = Text("as of \(usage.observedAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: zone)))")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.faint)
            if size == .large {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 48) {
                        ForEach(windows, id: \.0) { name, window in ring(name, window) }
                    }
                    asOf
                }
            } else {
                // One row, so the sessions above keep their room in a medium tile.
                HStack(alignment: .bottom, spacing: 28) {
                    ForEach(windows, id: \.0) { name, window in bar(name, window) }
                    asOf.fixedSize()
                }
            }
        } else {
            Text("Usage appears after your next Claude Code reply")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.faint)
        }
    }

    private func bar(_ name: String, _ window: UsageReading.Window) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(window.line(name, now: now, timeZone: zone, locale: locale))
                .font(Theme.Font.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.muted)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.Palette.surface)
                    Capsule()
                        .fill(UsageReading.Level(window.usedPercentage).color)
                        .frame(width: proxy.size.width * min(max(window.usedPercentage, 0), 100) / 100)
                }
            }
            .frame(height: 10)
            .animation(Theme.Motion.data, value: window.usedPercentage)
        }
        .accessibilityElement(children: .combine)
    }

    private func ring(_ name: String, _ window: UsageReading.Window) -> some View {
        HStack(spacing: 20) {
            ZStack {
                UsageRing(percentage: window.usedPercentage, diameter: 120, lineWidth: 12)
                Text(window.percent)
                    .font(Theme.Font.label)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.bone)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(name)
                    .font(Theme.Font.label)
                    .foregroundStyle(Theme.Palette.muted)
                Text("resets \(window.resets(now: now, timeZone: zone, locale: locale))")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.faint)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
