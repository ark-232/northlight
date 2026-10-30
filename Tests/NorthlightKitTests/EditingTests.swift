import Foundation
import Testing
@testable import NorthlightKit

// The starter's first page, Today: weather L, agenda M, aurora S, daylight S, all eight cells.

@Test func aCarriedWidgetMovesAndBackPutsItWhereItWas() {
    var editing = Editing(.starter)
    let aurora = editing.pages[0].placements[2].id
    editing.pickUp(aurora)
    #expect(editing.carried == Editing.Carried(id: aurora, page: 0, from: 2))
    editing.move(to: 0)
    #expect(editing.pages[0].placements.first?.id == aurora)
    editing.putBack()
    #expect(editing.pages == Dashboard.starter.pages)
    #expect(editing.carried == nil)

    editing.pickUp(aurora)
    editing.move(to: 0)
    editing.drop()
    #expect(editing.carried == nil)
    #expect(editing.pages[0].placements.first?.id == aurora)
}

@Test func theCarriedWidgetsSlotsAreTheGridsOwn() {
    var editing = Editing(.starter)
    let aurora = editing.pages[0].placements[2]
    editing.pickUp(aurora.id)
    let others = editing.pages[0].placements.filter { $0.id != aurora.id }.map(\.size)
    #expect(editing.slots == PageGrid.slots(for: .small, among: others, near: 2))
}

@Test func aWidgetResizesOnlyToSizesItTakesThatFit() {
    var editing = Editing(.starter)
    let aurora = editing.pages[0].placements[2].id, daylight = editing.pages[0].placements[3].id
    // The page is full, so the aurora cannot grow until something leaves.
    #expect(editing.sizes(for: aurora) == [.small])
    editing.remove(daylight)
    #expect(editing.sizes(for: aurora) == [.small, .medium])
    editing.resize(aurora, to: .medium)
    #expect(editing.pages[0].placements.first { $0.id == aurora }?.size == .medium)
}

@Test func anAddedWidgetGoesWhereItFitsOrOnANewPage() {
    var editing = Editing(.starter)
    // Today is full and Nearby has one cell, so GitHub starts a page of its own.
    #expect(editing.add(.github, size: .medium, preferring: 0) == 2)
    #expect(editing.pages.map(\.name) == ["Today", "Nearby", "Page 3"])
    #expect(editing.pages[2].placements.map(\.config) == [.github])
    // Nearby has a cell to spare.
    #expect(editing.add(.daylight, size: .small, preferring: 1) == 1)
}

@Test func aWidgetThatDoesNotFitOnScreenTakesRoomOnAnotherPage() {
    var editing = Editing(.starter)
    #expect(editing.add(.aurora, size: .small, preferring: 0) == 1)
    #expect(editing.pages.count == 2)
}

@Test func aNewPageIsNamedApartFromTheOthers() throws {
    // Page 2 was emptied and went, so counting alone would name the new page Page 3 again.
    let pages = try ["Today", "Page 3"].map { name in
        try #require(Page(name: name, placements: [Placement(config: .weather, size: .large)!,
                                                   Placement(config: .flights, size: .large)!]))
    }
    var editing = Editing(try #require(Dashboard(pages: pages)))
    #expect(editing.add(.github, size: .medium, preferring: 0) == 2)
    #expect(editing.pages.map(\.name) == ["Today", "Page 3", "Page 4"])
}

@Test func addingStopsAtSixFullPages() throws {
    let full = try (1...6).map { number in
        try #require(Page(name: "Full \(number)", placements: [Placement(config: .weather, size: .large)!,
                                                              Placement(config: .flights, size: .large)!]))
    }
    var editing = Editing(try #require(Dashboard(pages: full)))
    #expect(editing.add(.github, size: .medium, preferring: 5) == nil)
    #expect(editing.pages == full)
}

@Test func emptiedPagesGoWhenEditingEnds() {
    var editing = Editing(.starter)
    for placement in editing.pages[1].placements { editing.remove(placement.id) }
    // An emptied page stays while editing, so a widget can be added back to it.
    #expect(editing.pages.count == 2)
    #expect(editing.dashboard.pages.map(\.name) == ["Today"])
}

@Test func theLastWidgetStays() throws {
    var editing = Editing(.starter)
    let widgets = editing.pages.flatMap(\.placements)
    for placement in widgets.dropLast() {
        #expect(editing.canRemove)
        editing.remove(placement.id)
    }
    #expect(!editing.canRemove)
    #expect(editing.dashboard.pages.flatMap(\.placements) == [try #require(widgets.last)])
}

@Test func editsToAWidgetThatIsGoneChangeNothing() {
    // A Mac can remove a widget while the TV still shows its menu.
    var editing = Editing(.starter)
    let gone = UUID()
    #expect(editing.sizes(for: gone) == nil)
    #expect(editing.pickUp(gone) == nil)
    #expect(editing.resize(gone, to: .small) == nil)
    #expect(editing.remove(gone) == nil)
    #expect(editing.pages == Dashboard.starter.pages)
    #expect(editing.carried == nil)
}

@Test func aResizeThatNoLongerFitsChangesNothing() {
    var editing = Editing(.starter)
    let aurora = editing.pages[0].placements[2]
    // Today is full, so a size picked before another widget arrived no longer fits.
    #expect(editing.resize(aurora.id, to: .medium) == nil)
    #expect(editing.pages == Dashboard.starter.pages)
    #expect(editing.resize(aurora.id, to: .large) == nil)
}

@Test func editsReturnWhatTheyChanged() throws {
    var editing = Editing(.starter)
    let daylight = editing.pages[0].placements[3]
    #expect(editing.remove(daylight.id) == daylight)
    let aurora = editing.pages[0].placements[2]
    #expect(editing.resize(aurora.id, to: .medium)?.size == .medium)
    #expect(editing.pickUp(aurora.id) == Editing.Carried(id: aurora.id, page: 0, from: 2))
}
