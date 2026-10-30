import Charts
import NorthlightKit
import SwiftUI

/// The Network widget's detail on one screen: the path with its addresses, six hours of
/// round trips, and the M-Lab tester with its history. `action` is the button that
/// runs a test, which the app owns because it asks first.
public struct NetworkScreen<Action: View>: View {
    let path: NetworkPath?
    let latency: LatencyHistory
    /// Oldest first.
    let tests: [SpeedResult]
    let throughput: [ThroughputPoint]
    let running: Bool
    let error: String?
    /// The tests in the last 24 hours and when the next automatic one runs; nil while
    /// automatic tests are off.
    let automatic: (count: Int, next: Date?)?
    let now: Date
    @ViewBuilder let action: Action

    public init(path: NetworkPath?, latency: LatencyHistory, tests: [SpeedResult], throughput: [ThroughputPoint],
                running: Bool, error: String?, automatic: (count: Int, next: Date?)?, now: Date,
                @ViewBuilder action: () -> Action) {
        self.path = path
        self.latency = latency
        self.tests = tests
        self.throughput = throughput
        self.running = running
        self.error = error
        self.automatic = automatic
        self.now = now
        self.action = action()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 36) {
            HStack(alignment: .top, spacing: 40) {
                Text("Network")
                    .font(Theme.Font.clock)
                    .foregroundStyle(Theme.Palette.bone)
                Spacer(minLength: 0)
                if let path {
                    PathStrip(path: path, latency: latency, detailed: true, server: tests.last?.server)
                        .padding(.top, 12)
                } else {
                    TilePlaceholder(text: "Checking")
                }
            }
            HStack(alignment: .top, spacing: 64) {
                monitor
                    .frame(maxWidth: .infinity, alignment: .leading)
                tester
                    .frame(width: 720, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var monitor: some View {
        let end = latency.internet.last?.date ?? now
        let window: TimeInterval = 6 * 3_600
        let internet = LatencyStats(latency.internet.filter { $0.date > end - window })
        let gateway = LatencyStats(latency.gateway.filter { $0.date > end - window })
        return VStack(alignment: .leading, spacing: 20) {
            Heading(title: "Round trips", caption: "This Apple TV, a TCP connect every 30 s")
            LatencyChart(latency: latency, end: end, window: window, axes: true)
                .frame(height: 420)
            HStack(alignment: .top, spacing: 60) {
                VStack(alignment: .leading, spacing: 4) {
                    LatencyReading(stats: internet)
                    Text("to \(LatencyMonitor.internetHost), \(Latency.window(since: internet.since, end: end, window: window))")
                    if internet.failed > 0 {
                        Text("\(internet.failed) failed")
                            .foregroundStyle(Theme.Palette.amber)
                            .numericChange(internet.failed)
                    }
                }
                if !latency.gatewayHidden {
                    VStack(alignment: .leading, spacing: 4) {
                        LatencyReading(stats: gateway)
                        Text("to the router, dashed")
                        if gateway.failed > 0 {
                            Text("\(gateway.failed) failed")
                                .foregroundStyle(Theme.Palette.amber)
                                .numericChange(gateway.failed)
                        }
                    }
                }
            }
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.muted)
        }
    }

    private var tester: some View {
        VStack(alignment: .leading, spacing: 20) {
            Heading(title: "Speed test", caption: "M-Lab, about 20 s")
            if running {
                let current = throughput.last
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Image(systemName: current?.direction == .upload ? "arrow.up" : "arrow.down")
                            .font(Theme.Font.title)
                            .foregroundStyle(Theme.Palette.muted)
                        Text(current.map { Latency.megabits($0.megabits) } ?? "Finding a server")
                            .font(current == nil ? Theme.Font.title : Theme.Font.live)
                            .foregroundStyle(Theme.Palette.bone)
                            .numericChange(current?.megabits)
                    }
                    Text(current?.direction == .upload ? "Uploading" : "Downloading")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.muted)
                }
            } else if let last = tests.last {
                VStack(alignment: .leading, spacing: 8) {
                    SpeedNumbers(speed: last)
                    Text("\(Latency.number(last.idleLatency)) ms idle, \(Latency.number(last.loadedLatency)) ms loaded, \(Int(last.rpm)) RPM, \(last.responsiveness.rawValue)")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Palette.muted)
                    Text("\(last.server), \(last.date.formatted(date: .abbreviated, time: .shortened))")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.faint)
                }
            } else {
                Text("No speed test yet")
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Palette.muted)
            }
            if !throughput.isEmpty {
                ThroughputChart(points: throughput)
                    .frame(height: 130)
            }
            action
            if let error {
                Text(error)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.amber)
                    .lineLimit(2)
            }
            if tests.count > 1 {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        Text("\(tests.count) stored tests:")
                        Text("down").foregroundStyle(Theme.Kind.tint(.network))
                        Text("up").foregroundStyle(Theme.Palette.violet)
                    }
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.faint)
                    SpeedHistory(tests: tests)
                        .frame(height: throughput.isEmpty ? 200 : 100)
                }
            }
            if let automatic {
                Text(automaticWords(automatic))
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.faint)
            }
        }
    }

    private func automaticWords(_ automatic: (count: Int, next: Date?)) -> String {
        let next = automatic.next.map { "; next automatic test at \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
        return "\(automatic.count) of 4 tests in the last 24 h\(next)"
    }

    private struct Heading: View {
        let title: String
        let caption: String

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Text(title)
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Palette.bone)
                Text(caption)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.faint)
            }
            .lineLimit(1)
        }
    }
}

/// A test's speed as it ran, one line a direction, each ending on its result.
struct ThroughputChart: View {
    let points: [ThroughputPoint]

    var body: some View {
        Chart(Array(points.enumerated()), id: \.offset) { point in
            LineMark(x: .value("Seconds", point.element.seconds), y: .value("Mbps", point.element.megabits),
                     series: .value("Direction", point.element.direction == .download ? "Down" : "Up"))
                .foregroundStyle(point.element.direction == .download ? Theme.Kind.tint(.network) : Theme.Palette.violet)
                .lineStyle(StrokeStyle(lineWidth: 3))
        }
        .chartXScale(domain: 0...max(10, points.map(\.seconds).max() ?? 0))
        .chartXAxis(.hidden)
        .chartYAxis { megabitAxis() }
        .animation(Theme.Motion.data, value: points.count)
    }
}

/// Every stored test, down and up, as points over the days they ran.
struct SpeedHistory: View {
    let tests: [SpeedResult]

    var body: some View {
        Chart {
            ForEach(tests, id: \.date) { test in
                PointMark(x: .value("Date", test.date), y: .value("Mbps", test.downloadMegabits))
                    .foregroundStyle(Theme.Kind.tint(.network))
                    .symbolSize(120)
                PointMark(x: .value("Date", test.date), y: .value("Mbps", test.uploadMegabits))
                    .foregroundStyle(Theme.Palette.violet)
                    .symbolSize(120)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.faint)
            }
        }
        .chartYAxis { megabitAxis() }
    }
}

/// Two Mbps labels with their grid lines.
private func megabitAxis() -> some AxisContent {
    AxisMarks(values: .automatic(desiredCount: 2)) { value in
        AxisGridLine().foregroundStyle(Theme.Palette.hairline)
        AxisValueLabel {
            if let megabits = value.as(Double.self) {
                Text("\(Int(megabits))")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.faint)
            }
        }
    }
}
