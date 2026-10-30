import Charts
import NorthlightKit
import SwiftUI

/// The GitHub widget's detail on one 1760 × 960 screen, nothing to scroll: lines of
/// code by repository and the viewer's own weekly lines on the left, the year's
/// contributions and twelve commits on the right.
public struct GitHubDetail: View {
    let github: Loaded<GitHubSummary>?
    let lines: Loaded<CodeHistory>?
    let now: Date

    public init(snapshot: Snapshot) {
        github = snapshot.github
        lines = snapshot.codeHistory
        now = snapshot.now
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            HStack(alignment: .firstTextBaseline, spacing: 16) {
                Image(systemName: Theme.Kind.symbol(.github))
                    .foregroundStyle(Theme.Kind.tint(.github))
                Text("GitHub")
                    .foregroundStyle(Theme.Palette.bone)
                if let login = github?.value?.login {
                    Text(login)
                        .foregroundStyle(Theme.Palette.muted)
                }
                Spacer()
                if let trailing = github?.trailing(asOf: now) {
                    Text(trailing)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.amber)
                }
            }
            .font(Theme.Font.title)
            if let github {
                FeedBody(state: github.state(asOf: now)) { summary in
                    HStack(alignment: .top, spacing: 80) {
                        VStack(alignment: .leading, spacing: 28) {
                            DetailSection("Lines of code") {
                                LinesState(lines: lines, now: now) { RepositoryLines(history: $0) }
                            }
                            DetailSection("Your lines, 12 weeks") {
                                WeeklyLines(weeks: summary.weeks)
                                    .frame(height: 220)
                                Text(summary.linesTruncated
                                     ? "Your commits, merges left out, the largest clamped; older weeks partly counted"
                                     : "Your commits, merges left out, the largest clamped")
                                    .font(Theme.Font.caption)
                                    .foregroundStyle(Theme.Palette.faint)
                                    .lineLimit(1)
                            }
                        }
                        .frame(width: 840, alignment: .leading)
                        VStack(alignment: .leading, spacing: 28) {
                            DetailSection("\(summary.totalContributions) contributions in the last year") {
                                YearHeatmap(summary: summary)
                            }
                            DetailSection("Recent commits") {
                                CommitList(commits: Array(summary.commits.prefix(12)), now: now, showsCounts: true)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                TilePlaceholder(text: "Connect GitHub in Settings")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(Theme.Font.label)
                .foregroundStyle(Theme.Palette.muted)
            content
        }
    }
}

/// A year of each repository's running line count, stacked, with each one's total
/// beneath and any repository GitHub would not count named.
struct RepositoryLines: View {
    let history: CodeHistory
    var chartHeight: CGFloat = 320

    private struct Point: Identifiable {
        var repository: String
        var start: Date
        var lines: Int
        var id: String { "\(repository) \(start.timeIntervalSince1970)" }
    }

    var body: some View {
        let starts = Array(history.weekStarts.suffix(52))
        let names = history.repositories.map(\.shortName)
        let points = history.repositories.flatMap { repository in
            zip(starts, history.lines(of: repository).suffix(52)).map {
                Point(repository: repository.shortName, start: $0.0, lines: $0.1)
            }
        }
        VStack(alignment: .leading, spacing: 12) {
            Chart(points) { point in
                AreaMark(x: .value("Week", point.start), y: .value("Lines", point.lines), stacking: .standard)
                    .foregroundStyle(by: .value("Repository", point.repository))
                    .interpolationMethod(.monotone)
            }
            .chartForegroundStyleScale(domain: names, range: names.indices.map(RepositoryLines.color))
            .chartLegend(.hidden)
            .chartXAxis {
                AxisMarks(values: starts.count >= 6 ? [starts.count / 6, starts.count / 2, starts.count * 5 / 6].map { starts[$0] } : []) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.faint)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine().foregroundStyle(Theme.Palette.hairline)
                    AxisValueLabel {
                        if let lines = value.as(Int.self) {
                            Text(lines.compact)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.faint)
                        }
                    }
                }
            }
            .animation(Theme.Motion.data, value: history)
            .frame(height: chartHeight)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading), count: 3), alignment: .leading, spacing: 6) {
                ForEach(Array(history.repositories.enumerated()), id: \.element.name) { index, repository in
                    HStack(spacing: 10) {
                        Circle().fill(RepositoryLines.color(index)).frame(width: 16, height: 16)
                        Text(repository.shortName)
                            .foregroundStyle(Theme.Palette.bone)
                            .lineLimit(1)
                        Text((history.lines(of: repository).last ?? 0).compact)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Palette.muted)
                    }
                    .font(Theme.Font.caption)
                }
            }
            Text("Net lines, added minus deleted, all authors in your top \(history.repositories.count) repos, forks left out")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.faint)
            if !history.skipped.isEmpty {
                Text("\(history.skipped.map { $0.split(separator: "/").last.map(String.init) ?? $0 }.joined(separator: ", ")): too many commits to count")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.amber)
                    .lineLimit(1)
            }
        }
    }

    /// The kind's green, fading by rank.
    static func color(_ index: Int) -> Color {
        Theme.Kind.tint(.github).opacity([1, 0.78, 0.58, 0.42, 0.3][min(index, 4)])
    }
}

extension CodeHistory.Repository {
    var shortName: String { name.split(separator: "/").last.map(String.init) ?? name }
}

/// Lines added above the axis and deleted below it, week by week, the axis labelled
/// with signs so a deletion never reads as an addition.
private struct WeeklyLines: View {
    let weeks: [GitHubSummary.Week]

    var body: some View {
        Chart(weeks, id: \.start) { week in
            BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Lines", week.added))
                .foregroundStyle(Theme.Palette.green)
            BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Lines", -week.deleted))
                .foregroundStyle(Theme.Palette.red)
        }
        .chartXAxis {
            AxisMarks(values: weeks.count >= 12 ? [0, 5, 10].map { weeks[$0].start } : []) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day(), centered: true)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.faint)
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine().foregroundStyle(Theme.Palette.hairline)
                AxisValueLabel {
                    if let lines = value.as(Int.self) {
                        Text(lines == 0 ? "0" : lines > 0 ? lines.signedCompact : "\u{2212}\((-lines).compact)")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.faint)
                    }
                }
            }
        }
        .animation(Theme.Motion.data, value: weeks)
    }
}

/// The whole contribution calendar with month and weekday labels and a legend of
/// the five shades.
private struct YearHeatmap: View {
    let summary: GitHubSummary
    @Environment(\.calendar) private var calendar

    private let pitch: CGFloat = 14.5, gap: CGFloat = 3, labelWidth: CGFloat = 70, monthHeight: CGFloat = 34

    var body: some View {
        let weeks = (summary.levels.count + 6) / 7
        VStack(alignment: .leading, spacing: 14) {
            Canvas { context, _ in
                let cell = pitch - gap
                var lastMonth = -1
                for week in 0..<weeks {
                    let x = labelWidth + CGFloat(week) * pitch
                    if let day = calendar.date(byAdding: .day, value: week * 7, to: summary.firstDay) {
                        let month = calendar.component(.month, from: day)
                        if week > 0, month != lastMonth, week < weeks - 2 {
                            context.draw(Text(day.formatted(.dateTime.month(.abbreviated))).font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.faint), at: CGPoint(x: x, y: 0), anchor: .topLeading)
                        }
                        lastMonth = month
                    }
                    for row in 0..<7 {
                        let index = week * 7 + row
                        guard index < summary.levels.count else { break }
                        let square = CGRect(x: x, y: monthHeight + CGFloat(row) * pitch, width: cell, height: cell)
                        context.fill(Path(roundedRect: square, cornerRadius: 3), with: .color(ContributionStrip.shade(summary.levels[index])))
                    }
                }
                for (row, name) in [(1, "Mon"), (3, "Wed"), (5, "Fri")] {
                    context.draw(Text(name).font(Theme.Font.caption).foregroundStyle(Theme.Palette.faint),
                                 at: CGPoint(x: 0, y: monthHeight + CGFloat(row) * pitch + cell / 2), anchor: .leading)
                }
            }
            .frame(width: labelWidth + CGFloat(weeks) * pitch, height: monthHeight + 7 * pitch)
            .accessibilityLabel("\(summary.totalContributions) contributions in the last year")
            HStack(spacing: 8) {
                Text("Less")
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius: 3).fill(ContributionStrip.shade(level)).frame(width: 18, height: 18)
                }
                Text("More")
            }
            .font(Theme.Font.caption)
            .foregroundStyle(Theme.Palette.faint)
            .padding(.leading, labelWidth)
        }
    }
}
