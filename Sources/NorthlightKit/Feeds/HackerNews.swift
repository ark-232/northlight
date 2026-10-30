import Foundation

/// A story on the Hacker News front page.
public struct HNStory: Codable, Sendable, Equatable, Identifiable {
    public var id: Int
    public var title: String
    public var points: Int
    public var comments: Int
    public var time: Date

    public init(id: Int, title: String, points: Int, comments: Int, time: Date) {
        self.id = id; self.title = title; self.points = points; self.comments = comments; self.time = time
    }
}

public enum HackerNewsParsing {
    private struct Item: Decodable {
        var id: Int
        var title: String?
        var score: Int?
        var descendants: Int?
        var time: Double
        var dead: Bool?
        var deleted: Bool?
    }

    public static func topIDs(from data: Data) throws -> [Int] {
        try decodeFeed([Int].self, from: data)
    }

    /// Nil for an item that is dead, deleted or gone.
    public static func story(from data: Data) throws -> HNStory? {
        guard let item = try decodeFeed(Item?.self, from: data), item.dead != true, item.deleted != true,
              let title = item.title
        else { return nil }
        return HNStory(id: item.id, title: title, points: item.score ?? 0, comments: item.descendants ?? 0,
                       time: Date(timeIntervalSince1970: item.time))
    }
}

extension HTTP {
    /// The Hacker News Firebase API, keyless: the ranked IDs, then each story.
    public func hackerNews(count: Int = 5) async throws -> [HNStory] {
        let base = "https://hacker-news.firebaseio.com/v0/"
        let ids = try HackerNewsParsing.topIDs(from: await data(makeURL(base + "topstories.json"), accept: "application/json"))
        // A few spare, since a story can die between the two calls.
        let wanted = Array(ids.prefix(count + 3))
        let stories = await withTaskGroup(of: (Int, HNStory?).self) { group in
            for (rank, id) in wanted.enumerated() {
                group.addTask {
                    let story = try? HackerNewsParsing.story(from: await data(makeURL(base + "item/\(id).json"), accept: "application/json"))
                    return (rank, story)
                }
            }
            return await group.reduce(into: [Int: HNStory]()) { $0[$1.0] = $1.1 }
        }
        let ranked = wanted.indices.compactMap { stories[$0] }
        guard !ranked.isEmpty else { throw FeedError.decode("no readable stories") }
        return Array(ranked.prefix(count))
    }
}
