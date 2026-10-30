import Charts
import NorthlightKit
import SwiftUI

/// The viewer's contributions by week over a year, as GitHub's calendar counts them:
/// commits, pull requests, issues and reviews. This week so far is the hero.
struct GitHubContributionsTile: View {
    /// Nil until an account is connected here or on the Mac.
    let feed: Loaded<GitHubSummary>?
    let now: Date
    @Environment(\.widgetSize) private var size
    @Environment(\.calendar) private var calendar

    static let counted = "Commits, PRs, issues and reviews, by week"

    var body: some View {
        Tile(label: "Contributions", trailing: feed?.trailing(asOf: now)) {
            if let feed {
                FeedBody(state: feed.state(asOf: now)) { github in
                    let weeks = github.contributionWeeks(calendar: calendar)
                    if let thisWeek = weeks.last {
                        // This week is partial, so the average runs over the weeks before it.
                        let averages = GitHubSummary.trailingAverage(weeks.dropLast().map(\.count), over: 4)
                        let lately = Int((averages.last ?? 0).rounded())
                        if size == .large {
                            large(thisWeek: thisWeek.count, lately: lately, year: github.totalContributions,
                                  weeks: weeks, averages: averages)
                        } else {
                            medium(thisWeek: thisWeek.count, lately: lately, weeks: weeks, averages: averages)
                        }
                    } else {
                        TilePlaceholder(text: "No contributions yet")
                    }
                }
            } else {
                GitHubNotConnected()
            }
        }
    }

    private func medium(thisWeek: Int, lately: Int, weeks: [GitHubSummary.WeekCount], averages: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(thisWeek)")
                        .font(Theme.Font.hero)
                        .foregroundStyle(Theme.Palette.bone)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .numericChange(thisWeek)
                    Text("this week")
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Palette.muted)
                    Text("4-wk avg \(lately)")
                        .font(Theme.Font.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Palette.bone)
                        .lineLimit(1)
                }
                .frame(width: 210, alignment: .leading)
                ContributionWeeksChart(weeks: weeks, averages: averages)
            }
            .frame(height: 220)
            Text(Self.counted)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.faint)
                .lineLimit(1)
        }
    }

    private func large(thisWeek: Int, lately: Int, year: Int, weeks: [GitHubSummary.WeekCount], averages: [Double]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                Text("\(thisWeek)")
                    .font(Theme.Font.heroLarge)
                    .foregroundStyle(Theme.Palette.bone)
                    .lineLimit(1)
                    .numericChange(thisWeek)
                VStack(alignment: .leading, spacing: 4) {
                    Text("this week")
                        .font(Theme.Font.title)
                        .foregroundStyle(Theme.Palette.muted)
                    Text("4-week average \(lately)")
                        .font(Theme.Font.body)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Palette.bone)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 4) {
                    Text(year.formatted())
                        .font(Theme.Font.title)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Palette.bone)
                        .numericChange(year)
                    Text("in a year")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.muted)
                }
            }
            ContributionWeeksChart(weeks: weeks, averages: averages)
                .frame(height: 400)
            Text("\(Self.counted), as on your profile")
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.Palette.faint)
                .lineLimit(1)
        }
    }
}

/// A bar a week in the kind's green, this week's lighter for being partial, and the
/// four-week average over the weeks before it as a bone line.
private struct ContributionWeeksChart: View {
    let weeks: [GitHubSummary.WeekCount]
    let averages: [Double]
    private let tint = Theme.Kind.tint(.githubCommits)

    var body: some View {
        Chart {
            ForEach(Array(weeks.enumerated()), id: \.element.start) { index, week in
                BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Contributions", week.count))
                    .foregroundStyle(tint.opacity(index == weeks.count - 1 ? 0.45 : 0.9))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }
            ForEach(Array(averages.enumerated()), id: \.offset) { index, average in
                LineMark(x: .value("Week", weeks[index].start, unit: .weekOfYear), y: .value("Average", average))
                    .foregroundStyle(Theme.Palette.bone)
                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round))
                    .interpolationMethod(.monotone)
            }
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks(values: threeDates) { _ in
                AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.faint)
            }
        }
        .animation(Theme.Motion.data, value: weeks.map(\.count))
        .accessibilityHidden(true)
    }

    private var threeDates: [Date] {
        guard weeks.count >= 6 else { return [] }
        return [weeks.count / 6, weeks.count / 2, weeks.count * 5 / 6].map { weeks[$0].start }
    }
}
