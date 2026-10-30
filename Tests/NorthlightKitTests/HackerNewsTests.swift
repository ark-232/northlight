import Foundation
import Testing
@testable import NorthlightKit

/// The Hacker News Firebase API's top stories and the first of them, saved on
/// 20 Oct 2026.

@Test func topStoriesAreIDsInRankOrder() throws {
    let ids = try HackerNewsParsing.topIDs(from: fixture("hn-top"))
    #expect(ids.count == 30)
    #expect(ids.prefix(3) == [50_160_494, 50_154_540, 50_159_341])
}

@Test func aStoryReadsItsTitlePointsAndComments() throws {
    let story = try #require(try HackerNewsParsing.story(from: fixture("hn-item")))
    #expect(story.id == 50_160_494)
    #expect(story.title == "OpenBSD 8.0")
    #expect(story.points == 48)
    #expect(story.comments == 9)
    #expect(story.time == Date(timeIntervalSince1970: 1_792_462_000))
}

@Test func aJobHasNoCommentsAndADeadItemIsSkipped() throws {
    let job = #"{"id":1,"type":"job","title":"Northlight is hiring","score":1,"time":1792462000}"#
    #expect(try HackerNewsParsing.story(from: Data(job.utf8))?.comments == 0)
    let dead = #"{"id":2,"type":"story","dead":true,"time":1792462000}"#
    #expect(try HackerNewsParsing.story(from: Data(dead.utf8)) == nil)
    #expect(try HackerNewsParsing.story(from: Data("null".utf8)) == nil)
}
