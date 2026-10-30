import Foundation
import Testing
@testable import NorthlightKit

// The starter: Today holds weather L, agenda M, aurora S, daylight S; Nearby holds
// flights L, seismic M, air S.

private let today = Dashboard.starter.pages[0], nearby = Dashboard.starter.pages[1]

@Test func aWidgetMovesWithinItsPage() throws {
    let aurora = today.placements[2]
    let moved = try #require(Dashboard.starter.moving(aurora.id, toPage: 0, at: 0))
    #expect(moved.pages[0].placements.map(\.id) == [aurora.id, today.placements[0].id, today.placements[1].id, today.placements[3].id])
}

@Test func aWidgetMovesToAPageWithRoomOrNotAtAll() throws {
    let air = nearby.placements[2], agenda = today.placements[1]
    // Today is full; Nearby has one cell to spare.
    #expect(Dashboard.starter.moving(air.id, toPage: 0, at: 0) == nil)
    #expect(Dashboard.starter.moving(agenda.id, toPage: 1, at: 0) == nil)
    let daylight = today.placements[3]
    let moved = try #require(Dashboard.starter.moving(daylight.id, toPage: 1, at: 3))
    #expect(moved.pages[1].placements.last == daylight)
    #expect(moved.pages[0].placements.count == 3)
}

@Test func aWidgetMovedPastTheLastPageStartsOne() throws {
    let moved = try #require(Dashboard.starter.moving(today.placements[0].id, toPage: 2, at: 0))
    #expect(moved.pages.map(\.name) == ["Today", "Nearby", "Page 3"])
}

@Test func aPageEmptiedByAMoveGoes() throws {
    let solo = try #require(Page(name: "Solo", placements: [nearby.placements[2]]))
    let single = try #require(Dashboard(pages: [today, solo]))
    let moved = try #require(single.moving(nearby.placements[2].id, toPage: 2, at: 0))
    #expect(moved.pages.map(\.name) == ["Today", "Page 3"])
}

@Test func aWidgetIsAddedWhereItIsDropped() throws {
    let github = try #require(Placement(config: .github, size: .medium))
    #expect(Dashboard.starter.adding(github, toPage: 0, at: 0) == nil)
    let added = try #require(Dashboard.starter.adding(github, toPage: 2, at: 0))
    #expect(added.pages[2].placements == [github])
    let small = try #require(Placement(config: .daylight, size: .small))
    let withSmall = try #require(Dashboard.starter.adding(small, toPage: 1, at: 1))
    #expect(withSmall.pages[1].placements[1] == small)
}

@Test func theSeventhPageIsRefused() throws {
    let full = try (1...6).map { number in
        try #require(Page(name: "Full \(number)", placements: [Placement(config: .weather, size: .large)!,
                                                              Placement(config: .flights, size: .large)!]))
    }
    let six = try #require(Dashboard(pages: full))
    #expect(six.adding(Placement(config: .github, size: .medium)!, toPage: 6, at: 0) == nil)
}

@Test func removingAndResizingRefuseWhatCannotBe() throws {
    let aurora = today.placements[2]
    #expect(Dashboard.starter.resizing(aurora.id, to: .medium) == nil)
    #expect(Dashboard.starter.removing(UUID()) == nil)
    let removed = try #require(Dashboard.starter.removing(today.placements[3].id))
    let resized = try #require(removed.resizing(aurora.id, to: .medium))
    #expect(resized.pages[0].placements[2].size == .medium)
    let one = try #require(Page(name: "One", placements: [aurora]))
    let lone = try #require(Dashboard(pages: [one]))
    #expect(lone.removing(aurora.id) == nil)
}

@Test func pagesRenameAndReorder() throws {
    let renamed = try #require(Dashboard.starter.renaming(page: nearby.id, to: "  Outside  "))
    #expect(renamed.pages[1].name == "Outside")
    #expect(Dashboard.starter.renaming(page: nearby.id, to: "   ") == nil)
    // Names stay short enough for the TV's chips.
    let long = try #require(Dashboard.starter.renaming(page: nearby.id, to: String(repeating: "x", count: 40)))
    #expect(long.pages[1].name.count == Page.maxNameLength)
    let reordered = try #require(Dashboard.starter.movingPage(from: 1, to: 0))
    #expect(reordered.pages.map(\.name) == ["Nearby", "Today"])
}
