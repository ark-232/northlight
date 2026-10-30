import Charts
import NorthlightKit
import SwiftUI

/// What is waiting on the owner, the code in their busiest repositories, the year's
/// contribution calendar and their latest commits.
struct GitHubTile: View {
    /// Nil until an account is connected, like `lines`.
    let feed: Loaded<GitHubSummary>?
    let lines: Loaded<CodeHistory>?
    let now: Date
    @Environment(\.widgetSize) private var size

    var body: some View {
        Tile(label: "GitHub", trailing: feed?.trailing(asOf: now)) {
            if let feed {
                FeedBody(state: feed.state(asOf: now)) { github in
                    if size == .large {
                        VStack(alignment: .leading, spacing: 16) {
                            GitHubCounts(github: github)
                            LinesHero(lines: lines, now: now)
                            ContributionStrip(levels: github.levels)
                                .frame(height: ContributionStrip.height)
                            CommitList(commits: Array(github.commits.prefix(3)), now: now)
                        }
                    } else {
                        VStack(alignment: .leading, spacing: 14) {
                            GitHubCounts(github: github)
                            HStack(alignment: .top, spacing: 28) {
                                ContributionStrip(levels: github.levels)
                                LinesSparkline(lines: lines, now: now)
                                    .frame(width: 240)
                            }
                            .frame(height: ContributionStrip.height)
                            CommitList(commits: Array(github.commits.prefix(1)), now: now)
                        }
                    }
                }
            } else {
                TilePlaceholder(text: "Connect GitHub in Settings")
            }
        }
    }
}

/// "1 PR open · 0 to review · 2 issues".
private struct GitHubCounts: View {
    let github: GitHubSummary

    var body: some View {
        let pulls = github.openPullRequests, issues = github.assignedIssues
        Text("\(pulls) \(pulls == 1 ? "PR" : "PRs") open · \(github.reviewRequests) to review · \(issues) \(issues == 1 ? "issue" : "issues")")
            .font(Theme.Font.body)
            .monospacedDigit()
            .foregroundStyle(Theme.Palette.bone)
            .lineLimit(1)
            .numericChange([pulls, github.reviewRequests, issues])
    }
}

extension CodeHistory {
    /// The total at each week, the last `count` weeks.
    func recentTotals(_ count: Int) -> [LinePoint] {
        zip(weekStarts, totals).suffix(count).map { LinePoint(start: $0.0, lines: $0.1) }
    }
}

struct LinePoint: Equatable {
    var start: Date
    var lines: Int
}

extension Int {
    /// "412K", "+6.1K".
    var compact: String { formatted(.number.notation(.compactName)) }
    var signedCompact: String { formatted(.number.notation(.compactName).sign(strategy: .always(includingZero: false))) }
}

/// The lines in the tile's repositories as a number, its change over four weeks, and
/// a year of the running total.
struct LinesHero: View {
    let lines: Loaded<CodeHistory>?
    let now: Date
    var chartHeight: CGFloat = 200

    var body: some View {
        LinesState(lines: lines, now: now) { history in
            let points = history.recentTotals(52)
            if !points.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    LinesHeadline(points: points, font: Theme.Font.tileValue)
                    Text("Added minus deleted in \(history.repositories.count) repos, all authors, forks left out")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.faint)
                        .lineLimit(1)
                    LinesChart(points: points)
                        .frame(height: chartHeight)
                }
            } else {
                TilePlaceholder(text: "No lines to count")
            }
        }
    }
}

/// "412K lines   +6.1K in 4 weeks", the change unclamped: a deletion counts down.
struct LinesHeadline: View {
    let points: [LinePoint]
    let font: Font

    var body: some View {
        let last = points.last?.lines ?? 0
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Text(last.compact)
                .font(font)
                .foregroundStyle(Theme.Palette.bone)
                .lineLimit(1)
                .numericChange(last)
            Text("net lines")
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.muted)
            Spacer(minLength: 12)
            if points.count > 4 {
                let delta = last - points[points.count - 5].lines
                Text("\(delta.signedCompact) in 4 weeks")
                    .font(Theme.Font.body)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.bone)
                    .lineLimit(1)
                    .numericChange(delta)
            }
        }
    }
}

/// The medium tile's total and a half-year line under it.
private struct LinesSparkline: View {
    let lines: Loaded<CodeHistory>?
    let now: Date

    var body: some View {
        LinesState(lines: lines, now: now) { history in
            let points = history.recentTotals(26)
            if let last = points.last {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(last.lines.compact)
                            .font(Theme.Font.title)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Palette.bone)
                            .numericChange(last.lines)
                        Text("net lines")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.muted)
                    }
                    LinesChart(points: points, axis: false)
                }
            }
        }
    }
}

/// Lines of code once they are counted; while GitHub computes them, or before the
/// first answer, a sentence and no placeholder curve.
struct LinesState<Content: View>: View {
    let lines: Loaded<CodeHistory>?
    let now: Date
    @ViewBuilder let content: (CodeHistory) -> Content

    var body: some View {
        switch lines?.state(asOf: now) {
        case .ready(let history):
            content(history)
        case .unavailable(let reason) where reason != CodeHistory.counting:
            Text("Lines unavailable: \(reason)")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.faint)
                .lineLimit(2)
        default:
            Text(CodeHistory.counting)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.faint)
        }
    }
}

/// A running total as a filled curve in the kind's tint, its latest week marked. It
/// rises from the baseline when its first data arrives, not on every appearance.
struct LinesChart: View {
    let points: [LinePoint]
    var axis = true
    @State private var risen = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let tint = Theme.Kind.tint(.github)

    var body: some View {
        let low = points.map(\.lines).min() ?? 0, high = points.map(\.lines).max() ?? 0
        let floor = low - max((high - low) / 8, 1), ceiling = max(high, floor + 2)
        Chart {
            ForEach(points, id: \.start) { point in
                let y = risen ? point.lines : floor
                AreaMark(x: .value("Week", point.start), yStart: .value("Base", floor), yEnd: .value("Lines", y))
                    .foregroundStyle(LinearGradient(colors: [tint.opacity(0.45), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.monotone)
                LineMark(x: .value("Week", point.start), y: .value("Lines", y))
                    .foregroundStyle(tint)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
            if let last = points.last {
                PointMark(x: .value("Week", last.start), y: .value("Lines", risen ? last.lines : floor))
                    .symbolSize(700)
                    .foregroundStyle(tint.opacity(0.3))
                PointMark(x: .value("Week", last.start), y: .value("Lines", risen ? last.lines : floor))
                    .symbolSize(160)
                    .foregroundStyle(tint)
            }
        }
        .chartYScale(domain: floor...ceiling)
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: threeDates) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.faint)
            }
        }
        .chartXAxis(axis ? .automatic : .hidden)
        .animation(Theme.Motion.data, value: points)
        .onAppear(perform: rise)
        .accessibilityHidden(true)
    }

    private var threeDates: [Date] {
        guard points.count >= 6 else { return [] }
        return [points.count / 6, points.count / 2, points.count * 5 / 6].map { points[$0].start }
    }

    /// Rises the first time a series shows in this launch. A page turn rebuilds the
    /// chart, and rising on every visit would be motion with no news in it.
    private func rise() {
        guard !risen else { return }
        let series = points.first?.start ?? .distantPast
        if reduceMotion || LinesChart.risenSeries.contains(series) {
            risen = true
        } else {
            LinesChart.risenSeries.insert(series)
            withAnimation(Theme.Motion.data) { risen = true }
        }
    }

    private static var risenSeries: Set<Date> = []
}

/// The contribution calendar as columns of weeks, as many of the latest as fit at
/// 18 pt squares, in GitHub's five shades of the kind's green.
struct ContributionStrip: View {
    let levels: [Int]
    var cell: CGFloat = 18
    var gap: CGFloat = 4

    static let height: CGFloat = 7 * 22 - 4

    var body: some View {
        Canvas { context, size in
            let pitch = cell + gap
            let weeks = (levels.count + 6) / 7
            let shown = min(weeks, Int((size.width + gap) / pitch))
            let firstWeek = weeks - shown
            for (day, level) in levels.enumerated() where day / 7 >= firstWeek {
                let square = CGRect(x: CGFloat(day / 7 - firstWeek) * pitch, y: CGFloat(day % 7) * pitch, width: cell, height: cell)
                context.fill(Path(roundedRect: square, cornerRadius: cell * 0.22), with: .color(ContributionStrip.shade(level)))
            }
        }
        .accessibilityHidden(true)
    }

    static func shade(_ level: Int) -> Color {
        level <= 0 ? Theme.Palette.surface : Theme.Kind.tint(.github).opacity([0.3, 0.5, 0.75, 1][min(level, 4) - 1])
    }
}

/// The latest commits: repository, headline and age. A private repository shows its
/// line counts in place of the headline.
struct CommitList: View {
    let commits: [GitHubSummary.Commit]
    let now: Date
    var showsCounts = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(commits, id: \.oid) { commit in
                CommitRow(commit: commit, now: now, showsCounts: showsCounts)
                    .transition(.push(from: .top))
            }
        }
        .animation(Theme.Motion.insert, value: commits.map(\.oid))
    }
}

private struct CommitRow: View {
    let commit: GitHubSummary.Commit
    let now: Date
    let showsCounts: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(commit.repository)
                .font(Theme.Font.label)
                .foregroundStyle(Theme.Kind.tint(.github))
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.Palette.surface))
            if let headline = commit.headline {
                Text(headline)
                    .foregroundStyle(Theme.Palette.bone)
                    .lineLimit(1)
            }
            if showsCounts || commit.headline == nil {
                LineCounts(added: commit.additions, deleted: commit.deletions)
            }
            Spacer(minLength: 12)
            Text(max(0, now.timeIntervalSince(commit.date)).shortAge)
                .font(Theme.Font.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.faint)
        }
        .font(Theme.Font.body)
    }
}

/// "+48 −31" in green and red.
struct LineCounts: View {
    let added: Int
    let deleted: Int

    var body: some View {
        HStack(spacing: 8) {
            Text("+\(added.compact)").foregroundStyle(Theme.Palette.green)
            Text("\u{2212}\(deleted.compact)").foregroundStyle(Theme.Palette.red)
        }
        .monospacedDigit()
        .lineLimit(1)
        .fixedSize()
    }
}
