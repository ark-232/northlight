import Charts
import NorthlightKit
import SwiftUI

/// This Apple TV's path to the internet and how long a round trip takes along it, with
/// the last M-Lab test. Medium draws the path and 30 minutes of round trips; small, the
/// link and the internet round trip.
struct NetworkTile: View {
    /// Nil until the first reading.
    let path: NetworkPath?
    let latency: LatencyHistory
    let speed: SpeedResult?
    let now: Date
    @Environment(\.widgetSize) private var size

    var body: some View {
        Tile(label: "Network", accent: Theme.Kind.tint(.network)) {
            if let path {
                if size == .small {
                    small(path)
                } else {
                    medium(path)
                }
            } else {
                TilePlaceholder(text: "Checking")
            }
        }
    }

    private func small(_ path: NetworkPath) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(path.linkWords, systemImage: path.linkSymbol)
                .font(Theme.Font.body)
                .foregroundStyle(path.link == nil ? Theme.Palette.amber : Theme.Palette.bone)
                .lineLimit(1)
            let latest = latency.internet.last?.milliseconds
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(latest.map { Latency.number($0) } ?? (latency.internet.isEmpty ? "Probing" : "No answer"))
                    .font(latest == nil ? Theme.Font.title : Theme.Font.clock)
                    .numericChange(latest)
                if latest != nil {
                    Text("ms")
                        .font(Theme.Font.title)
                        .foregroundStyle(Theme.Palette.muted)
                }
            }
            .foregroundStyle(Theme.Palette.bone)
            Text("This Apple TV to \(LatencyMonitor.internetHost)")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.muted)
                .lineLimit(2)
            Spacer(minLength: 0)
            if let speed {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Label(Latency.megabits(speed.downloadMegabits), systemImage: "arrow.down")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Palette.bone)
                        .numericChange(speed.downloadMegabits)
                    Text(now.timeIntervalSince(speed.date).shortAge)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.faint)
                }
            } else {
                Text("No speed test yet")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.faint)
            }
        }
    }

    private func medium(_ path: NetworkPath) -> some View {
        let end = latency.internet.last?.date ?? now
        let window: TimeInterval = 30 * 60
        let recent = latency.internet.filter { $0.date > end - window }
        let stats = LatencyStats(recent)
        return VStack(alignment: .leading, spacing: 16) {
            PathStrip(path: path, latency: latency)
            HStack(alignment: .bottom, spacing: 28) {
                LatencyChart(latency: latency, end: end, window: window)
                    .frame(height: 112)
                VStack(alignment: .trailing, spacing: 2) {
                    LatencyReading(stats: stats)
                    Text(Latency.window(since: stats.since, end: end, window: window))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.faint)
                        .lineLimit(1)
                }
                .fixedSize()
            }
            HStack(alignment: .firstTextBaseline, spacing: 20) {
                if let speed {
                    Label(Latency.megabits(speed.downloadMegabits), systemImage: "arrow.down")
                        .numericChange(speed.downloadMegabits)
                    Label(Latency.megabits(speed.uploadMegabits), systemImage: "arrow.up")
                        .numericChange(speed.uploadMegabits)
                    Spacer(minLength: 12)
                    Text("M-Lab test, \(now.timeIntervalSince(speed.date).shortAge) ago")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.faint)
                } else {
                    Text("No speed test yet")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.faint)
                }
            }
            .font(Theme.Font.body)
            .foregroundStyle(Theme.Palette.bone)
            .lineLimit(1)
        }
    }
}

/// Words and colours for round trips and speeds, shared by the tile and the detail.
public enum Latency {
    /// One decimal under 10 ms, where a LAN's round trips sit.
    public static func number(_ milliseconds: Double) -> String {
        milliseconds < 10 ? milliseconds.formatted(.number.precision(.fractionLength(1))) : "\(Int(milliseconds.rounded()))"
    }

    /// A hop's last probe: "38 ms", "No answer", or "Probing" before the first.
    public static func words(_ sample: LatencySample?) -> String {
        guard let sample else { return "Probing" }
        return sample.milliseconds.map { "\(number($0)) ms" } ?? "No answer"
    }

    public static func megabits(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.significantDigits(...3)))) Mbps"
    }

    public static func color(_ milliseconds: Double?, onLAN: Bool) -> Color {
        guard let milliseconds else { return Theme.Palette.faint }
        switch LatencyGrade(milliseconds: milliseconds, onLAN: onLAN) {
        case .good: return Theme.Palette.green
        case .fair: return Theme.Palette.amber
        case .poor: return Theme.Palette.red
        }
    }

    /// "median, 30 min", or the time of the first probe while the ring is shorter.
    public static func window(since: Date?, end: Date, window: TimeInterval) -> String {
        guard let since, since > end - window + LatencyMonitor.interval / .seconds(1) else {
            return window >= 3_600 ? "median, \(Int(window / 3_600)) h" : "median, \(Int(window / 60)) min"
        }
        return "median since \(since.formatted(date: .omitted, time: .shortened))"
    }
}

/// The median round trip with its jitter, "38 ms ±4".
public struct LatencyReading: View {
    let stats: LatencyStats

    public init(stats: LatencyStats) {
        self.stats = stats
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            if let median = stats.median {
                Text("\(Latency.number(median)) ms")
                    .font(Theme.Font.tileValue)
                    .foregroundStyle(Theme.Palette.bone)
                    .numericChange(median)
                if let jitter = stats.jitter {
                    Text("±\(Latency.number(jitter))")
                        .font(Theme.Font.title)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Palette.muted)
                        .numericChange(jitter)
                }
            } else {
                Text(stats.failed > 0 ? "No answer" : "Probing")
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Palette.muted)
            }
        }
    }
}

/// This Apple TV, its link, the gateway if it answers, and the internet, each hop
/// coloured by its last round trip and crossed by a dot at each probe.
public struct PathStrip: View {
    let path: NetworkPath
    let latency: LatencyHistory
    /// Addresses under the hops, and the last test's server, as the detail shows them.
    var detailed = false
    var server: String?

    public init(path: NetworkPath, latency: LatencyHistory, detailed: Bool = false, server: String? = nil) {
        self.path = path
        self.latency = latency
        self.detailed = detailed
        self.server = server
    }

    public var body: some View {
        let online = path.link != nil
        let gateway = latency.gateway.last, internet = latency.internet.last
        HStack(spacing: 0) {
            Node(symbol: "appletv", tint: Theme.Palette.bone) {
                Text("This Apple TV")
                if detailed, let address = path.address { Text(address).foregroundStyle(Theme.Palette.faint) }
            }
            Hop(color: online ? path.qualityColor : Theme.Palette.faint, probe: nil)
            Node(symbol: path.linkSymbol, tint: online ? Theme.Palette.bone : Theme.Palette.amber) {
                Text(path.qualityWord)
            }
            if !latency.gatewayHidden {
                Hop(color: online ? Latency.color(gateway?.milliseconds, onLAN: true) : Theme.Palette.faint, probe: gateway?.date)
                Node(symbol: "wifi.router", tint: Theme.Palette.bone) {
                    Text(Latency.words(gateway))
                        .numericChange(gateway?.milliseconds)
                    if detailed, let address = path.gateway { Text(address).foregroundStyle(Theme.Palette.faint) }
                }
            }
            Hop(color: online ? Latency.color(internet?.milliseconds, onLAN: false) : Theme.Palette.faint, probe: internet?.date)
            Node(symbol: "globe", tint: Theme.Palette.bone) {
                Text(Latency.words(internet))
                    .numericChange(internet?.milliseconds)
                if detailed { Text(LatencyMonitor.internetHost).foregroundStyle(Theme.Palette.faint) }
            }
            if detailed, let server {
                Hop(color: Theme.Palette.faint, probe: nil)
                Node(symbol: "server.rack", tint: Theme.Palette.muted) {
                    Text(server)
                    Text("M-Lab").foregroundStyle(Theme.Palette.faint)
                }
            }
        }
        .padding(.horizontal, 60)
        .padding(.bottom, detailed ? 76 : 40)
        .accessibilityElement(children: .combine)
    }

    private struct Node<Caption: View>: View {
        let symbol: String
        let tint: Color
        @ViewBuilder var caption: Caption

        var body: some View {
            Image(systemName: symbol)
                .font(Theme.Font.title)
                .foregroundStyle(tint)
                .frame(width: 60, height: 48)
                .overlay(alignment: .top) {
                    VStack(spacing: 2) { caption }
                        .font(Theme.Font.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Palette.muted)
                        .lineLimit(1)
                        .fixedSize()
                        .offset(y: 54)
                }
        }
    }

    private struct Hop: View {
        let color: Color
        let probe: Date?
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            Capsule()
                .fill(color)
                .frame(height: 4)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 10)
                .overlay {
                    if let probe, !reduceMotion {
                        GeometryReader { geometry in
                            let travel = geometry.size.width - 34
                            Circle()
                                .fill(color)
                                .frame(width: 14, height: 14)
                                .keyframeAnimator(initialValue: 1.0, trigger: probe) { dot, progress in
                                    dot.offset(x: 10 + progress * travel).opacity(progress < 1 ? 1 : 0)
                                } keyframes: { _ in
                                    MoveKeyframe(0)
                                    LinearKeyframe(1, duration: 0.8)
                                }
                                .frame(maxHeight: .infinity)
                        }
                    }
                }
                .animation(Theme.Motion.data, value: color)
        }
    }
}

/// Round trips to the internet over `window`, ending at the last probe, with the
/// gateway's dashed; gaps where nothing answered or nothing ran.
public struct LatencyChart: View {
    let latency: LatencyHistory
    let end: Date
    let window: TimeInterval
    var axes = false

    public init(latency: LatencyHistory, end: Date, window: TimeInterval, axes: Bool = false) {
        self.latency = latency
        self.end = end
        self.window = window
        self.axes = axes
    }

    public var body: some View {
        let start = end - window
        let internet = Array(LatencyHistory.runs(latency.internet.filter { $0.date >= start }).enumerated())
        let gateway = latency.gatewayHidden ? []
            : Array(LatencyHistory.runs(latency.gateway.filter { $0.date >= start }).enumerated())
        Chart {
            ForEach(gateway, id: \.offset) { run in
                ForEach(run.element, id: \.date) { sample in
                    LineMark(x: .value("Time", sample.date), y: .value("ms", sample.milliseconds ?? 0),
                             series: .value("Run", "gateway \(run.offset)"))
                        .foregroundStyle(Theme.Palette.muted)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 6]))
                }
            }
            ForEach(internet, id: \.offset) { run in
                ForEach(run.element, id: \.date) { sample in
                    LineMark(x: .value("Time", sample.date), y: .value("ms", sample.milliseconds ?? 0),
                             series: .value("Run", "internet \(run.offset)"))
                        .foregroundStyle(Theme.Kind.tint(.network))
                        .lineStyle(StrokeStyle(lineWidth: 3))
                }
            }
        }
        .chartXScale(domain: start...end)
        .chartXAxis {
            if axes {
                AxisMarks(values: hours(from: start)) { _ in
                    AxisGridLine().foregroundStyle(Theme.Palette.hairline)
                    AxisValueLabel(format: .dateTime.hour().minute())
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.faint)
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 2)) { value in
                AxisGridLine().foregroundStyle(Theme.Palette.hairline)
                AxisValueLabel {
                    if let milliseconds = value.as(Double.self) {
                        Text("\(Int(milliseconds))")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.faint)
                    }
                }
            }
        }
        .animation(Theme.Motion.data, value: latency.internet.last?.date)
    }

    /// Three whole hours across the window, none so near its end that the label clips.
    private func hours(from start: Date) -> [Date] {
        var marks: [Date] = []
        var mark = Calendar.current.nextDate(after: start, matching: DateComponents(minute: 0, second: 0), matchingPolicy: .nextTime) ?? end
        while mark < end - window / 12 {
            marks.append(mark)
            mark += window / 3
        }
        return marks
    }
}

extension NetworkPath {
    var linkSymbol: String {
        switch link {
        case .ethernet: "cable.connector"
        case .wifi: "wifi"
        case .other: "network"
        case nil: "wifi.slash"
        }
    }

    var linkName: String {
        switch link {
        case .ethernet: "Ethernet"
        case .wifi: "Wi-Fi"
        case .other: "Connected"
        case nil: "Offline"
        }
    }

    /// The quality tvOS reports, else the link's name.
    var qualityWord: String {
        guard link != nil else { return "Offline" }
        switch quality {
        case .good: return "Good"
        case .moderate: return "Moderate"
        case .minimal: return "Weak"
        case nil: return linkName
        }
    }

    var linkWords: String {
        guard link != nil, quality != nil else { return linkName }
        return "\(linkName), \(qualityWord.lowercased())"
    }

    var qualityColor: Color {
        switch quality {
        case .good: Theme.Palette.green
        case .moderate: Theme.Palette.amber
        case .minimal: Theme.Palette.red
        case nil: Theme.Palette.faint
        }
    }
}

/// A speed test's download and upload, in megabits a second.
public struct SpeedNumbers: View {
    let speed: SpeedResult

    public init(speed: SpeedResult) {
        self.speed = speed
    }

    public var body: some View {
        // Side by side where they fit; stacked where they do not.
        ViewThatFits {
            HStack(alignment: .firstTextBaseline, spacing: 28) { numbers }
            VStack(alignment: .leading, spacing: 8) { numbers }
        }
        .font(Theme.Font.tileValue)
        .foregroundStyle(Theme.Palette.bone)
        .monospacedDigit()
    }

    @ViewBuilder private var numbers: some View {
        Label(Latency.megabits(speed.downloadMegabits), systemImage: "arrow.down")
        Label(Latency.megabits(speed.uploadMegabits), systemImage: "arrow.up")
    }
}
