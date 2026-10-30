import NorthlightKit
import SwiftUI

/// The top of the Hacker News front page: three stories, or five at large size.
struct HackerNewsTile: View {
    let feed: Loaded<[HNStory]>
    let now: Date
    @Environment(\.widgetSize) private var size
    @Environment(\.widgetKind) private var kind

    var body: some View {
        Tile(label: "Hacker News", trailing: feed.trailing(asOf: now)) {
            FeedBody(state: feed.state(asOf: now)) { stories in
                VStack(alignment: .leading, spacing: size == .large ? 22 : 14) {
                    ForEach(Array(stories.prefix(size == .large ? 5 : 3).enumerated()), id: \.element.id) { rank, story in
                        HStack(alignment: .firstTextBaseline, spacing: 18) {
                            Text("\(rank + 1)")
                                .font(Theme.Font.label)
                                .monospacedDigit()
                                .foregroundStyle(kind.map(Theme.Kind.tint) ?? Theme.Palette.muted)
                                .frame(width: 24, alignment: .trailing)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(story.title)
                                    .font(Theme.Font.body)
                                    .foregroundStyle(Theme.Palette.bone)
                                    .lineLimit(size == .large ? 2 : 1)
                                Text("\(story.points) points · \(story.comments) comments · \(now.timeIntervalSince(story.time).shortAge)")
                                    .font(Theme.Font.caption)
                                    .monospacedDigit()
                                    .foregroundStyle(Theme.Palette.faint)
                                    .lineLimit(1)
                            }
                        }
                        .transition(.opacity)
                    }
                }
                .animation(Theme.Motion.data, value: stories.map(\.id))
            }
        }
    }
}
