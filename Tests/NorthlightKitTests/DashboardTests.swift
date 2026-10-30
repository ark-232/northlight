import Foundation
import Testing
@testable import NorthlightKit

/// Every sequence of 1 to `length` widgets, each small, medium or large.
private func sequences(upTo length: Int) -> [[WidgetSize]] {
    var all: [[WidgetSize]] = [], layer: [[WidgetSize]] = [[]]
    for _ in 1...length {
        layer = layer.flatMap { prefix in WidgetSize.allCases.map { prefix + [$0] } }
        all += layer
    }
    return all
}

private func cells(_ origin: GridPoint, _ size: WidgetSize) -> [GridPoint] {
    (origin.row..<origin.row + size.rows).flatMap { row in
        (origin.col..<origin.col + size.cols).map { GridPoint(col: $0, row: row) }
    }
}

// MARK: - Packing

@Test func everyLayoutThatFitsIsPackedInsideTheGridWithoutOverlap() {
    let all = sequences(upTo: 8)
    let fitting = all.filter(PageGrid.fits)
    #expect(all.count == 9_840)
    #expect(fitting.count == 126)
    for sizes in fitting {
        let taken = zip(PageGrid.origins(for: sizes), sizes).flatMap { cells($0, $1) }
        #expect(Set(taken).count == taken.count, "\(sizes)")
        #expect(taken.allSatisfy { (0..<PageGrid.cols).contains($0.col) && (0..<PageGrid.rows).contains($0.row) }, "\(sizes)")
    }
}

@Test func slotsOfferEachReachableOriginOnceAtTheIndexNearestWhereTheWidgetStarted() {
    var cases = 0
    for sequence in sequences(upTo: 8) where PageGrid.fits(sequence) {
        let size = sequence.last!, others = Array(sequence.dropLast())
        for current in 0...others.count {
            cases += 1
            var reachable: [GridPoint: [Int]] = [:]
            for index in 0...others.count {
                var order = others
                order.insert(size, at: index)
                reachable[PageGrid.origins(for: order)[index], default: []].append(index)
            }
            let slots = PageGrid.slots(for: size, among: others, near: current)
            #expect(slots.count == reachable.count)
            #expect(Set(slots.map(\.origin)) == Set(reachable.keys))
            for slot in slots {
                let nearest = reachable[slot.origin]?.min { abs($0 - current) < abs($1 - current) }
                #expect(slot.index == nearest)
            }
            // Dropping a widget where it started leaves the page as it was.
            #expect(slots.contains { $0.index == current })
        }
    }
    #expect(cases == 560)
}

// MARK: - The document

@Test func aWidgetTakesOnlyItsOwnSizes() throws {
    #expect(Placement(config: .aurora, size: .large) == nil)
    #expect(Placement(config: .weather, size: .small) == nil)
    let json = Data(#"{"id":"5C0E5D69-6F7B-4E36-9C59-8A4F1B0E2C11","config":{"aurora":{}},"size":"large"}"#.utf8)
    #expect(throws: DecodingError.self) { try JSONDecoder().decode(Placement.self, from: json) }
}

@Test func aPageHoldsAtMostEightCells() throws {
    let large = try #require(Placement(config: .weather, size: .large))
    let small = try #require(Placement(config: .aurora, size: .small))
    #expect(Page(name: "Full", placements: [large, large]) != nil)
    #expect(Page(name: "Over", placements: [large, large, small]) == nil)
}

@Test func aDashboardHasOneToSixPagesEachWithAWidget() throws {
    let aurora = try #require(Placement(config: .aurora, size: .small))
    let page = try #require(Page(name: "Page", placements: [aurora]))
    let empty = try #require(Page(name: "Empty", placements: []))
    #expect(Dashboard(pages: []) == nil)
    #expect(Dashboard(pages: Array(repeating: page, count: 6)) != nil)
    #expect(Dashboard(pages: Array(repeating: page, count: 7)) == nil)
    #expect(Dashboard(pages: [page, empty]) == nil)
    let json = #"{"schemaVersion":1,"pages":[{"id":"5C0E5D69-6F7B-4E36-9C59-8A4F1B0E2C11","name":"Empty","placements":[]}]}"#
    #expect(throws: DecodingError.self) { try Dashboard(data: Data(json.utf8)) }
}

@Test func theStarterLayoutRoundTrips() throws {
    #expect(try Dashboard(data: Dashboard.starter.data()) == Dashboard.starter)
}

@Test func aSeismicWidgetStoresItsThresholdUnderItsName() throws {
    let json = try JSONEncoder().encode(WidgetConfig.seismic(minMagnitude: 3.5))
    #expect(String(decoding: json, as: UTF8.self) == #"{"seismic":{"minMagnitude":3.5}}"#)
}

@Test func aLayoutFromANewerVersionIsRefusedWithItsVersion() {
    let error = #expect(throws: Dashboard.NewerSchema.self) {
        try Dashboard(data: Data(#"{"schemaVersion":4,"pages":[]}"#.utf8))
    }
    #expect(error?.version == 4)
}

@Test func aVersionOneLayoutStillLoadsAndSavesAsVersionThree() throws {
    let json = #"{"schemaVersion":1,"pages":[{"id":"6A1E3C1F-6D1B-4E7A-9B57-0B3C0E2C4A11","name":"Today","placements":[{"id":"0F4B0F7E-3E1C-4C0A-8E44-5A0F2C3B6D21","config":{"network":{}},"size":"medium"}]}]}"#
    let dashboard = try Dashboard(data: Data(json.utf8))
    #expect(dashboard.pages.first?.placements.first?.config == .network)
    let saved = try JSONSerialization.jsonObject(with: dashboard.data()) as? [String: Any]
    #expect(saved?["schemaVersion"] as? Int == 3)
}

@Test func aVersionTwoLayoutStillLoads() throws {
    let json = #"{"schemaVersion":2,"pages":[{"id":"6A1E3C1F-6D1B-4E7A-9B57-0B3C0E2C4A11","name":"Code","placements":[{"id":"0F4B0F7E-3E1C-4C0A-8E44-5A0F2C3B6D21","config":{"github":{}},"size":"large"},{"id":"9C2D1A7B-6F3E-4B8C-A1D5-2E7F9B0C3A31","config":{"markets":{}},"size":"small"}]}]}"#
    let dashboard = try Dashboard(data: Data(json.utf8))
    #expect(dashboard.pages.first?.placements.map(\.config) == [.github, .markets])
}

/// Version 3 added the GitHub family: lines of code, contributions, the inbox and Actions.
@Test func theGitHubFamilyTakesItsSizesAndStoresUnderItsNames() throws {
    #expect(WidgetConfig.githubLines.sizes == [.medium, .large])
    #expect(WidgetConfig.githubCommits.sizes == [.medium, .large])
    #expect(WidgetConfig.githubInbox.sizes == [.medium, .large])
    #expect(WidgetConfig.githubActions.sizes == [.small, .medium, .large])
    let json = try JSONEncoder().encode([WidgetConfig.githubLines, .githubCommits, .githubInbox, .githubActions])
    #expect(String(decoding: json, as: UTF8.self) == #"[{"githubLines":{}},{"githubCommits":{}},{"githubInbox":{}},{"githubActions":{}}]"#)
    #expect(Dashboard.schema == 3)
}

@Test func everyKindIsInTheGalleryOnceUnderItsOwnName() {
    #expect(Set(WidgetConfig.all).count == WidgetConfig.all.count)
    #expect(Set(WidgetConfig.all.map(\.name)).count == WidgetConfig.all.count)
    for kind in [WidgetConfig.githubLines, .githubCommits, .githubInbox, .githubActions] {
        #expect(WidgetConfig.all.contains(kind))
    }
}

@Test func aLayoutOver64KBIsRefusedEitherWay() throws {
    let aurora = try #require(Placement(config: .aurora, size: .small))
    let page = try #require(Page(name: String(repeating: "x", count: 65 * 1_024), placements: [aurora]))
    let dashboard = try #require(Dashboard(pages: [page]))
    #expect(throws: Dashboard.TooLarge.self) { try dashboard.data() }
    let encoded = try JSONEncoder().encode(dashboard)
    #expect(throws: Dashboard.TooLarge.self) { try Dashboard(data: encoded) }
}

// MARK: - Storage

private func scratchDefaults() -> UserDefaults {
    let name = "northlight-layout-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Test func aFreshInstallShowsTheDefaultPages() {
    #expect(Dashboard.load(from: scratchDefaults()) == .defaults)
}

@Test func theDefaultPagesAreTodayOutsideSkyCodeAndDesk() throws {
    let pages = Dashboard.defaults.pages
    #expect(pages.map(\.name) == ["Today", "Outside", "Sky", "Code", "Desk"])
    let widgets = pages.map { $0.placements.map { "\($0.config.name) \($0.size.rawValue)" } }
    #expect(widgets == [
        ["Weather large", "Agenda medium", "Briefing medium"],
        ["Overhead large", "Seismic medium", "Air & snow small", "Network small"],
        ["Space weather large", "ISS medium", "Aurora small", "Daylight small"],
        ["GitHub large", "Contributions medium", "Actions medium"],
        ["Agents large", "GitHub inbox medium", "Hacker News medium"],
    ])
    #expect(pages[1].placements[1].config == .seismic(minMagnitude: 2.5))
    // Each page fills its eight cells and packs inside the grid.
    for page in pages {
        let sizes = page.placements.map(\.size)
        #expect(sizes.map(\.cells).reduce(0, +) == PageGrid.capacity)
        #expect(PageGrid.origins(for: sizes).count == sizes.count)
    }
    #expect(try Dashboard(data: Dashboard.defaults.data()) == .defaults)
}

@Test func aStoredLayoutLoads() throws {
    let defaults = scratchDefaults()
    let aurora = try #require(Placement(config: .aurora, size: .small))
    let page = try #require(Page(name: "Only", placements: [aurora]))
    let stored = try #require(Dashboard(pages: [page]))
    defaults.set(try stored.data(), forKey: "layout")
    #expect(Dashboard.load(from: defaults) == stored)
}

/// Restoring replaces every widget placed by hand, so the confirmation names them.
@Test func restoringTheDefaultPagesSaysWhatItReplaces() {
    let message = Dashboard.starter.restoringDefaultsMessage
    #expect(message.hasPrefix("This replaces Today and Nearby, 7 widgets in all, with Today, Outside, Sky, Code"))
    #expect(message.hasSuffix("Desk."))
}

@Test func anUnreadableLayoutLoadsAsTheDefaultPages() {
    let defaults = scratchDefaults()
    defaults.set(Data(#"{"schemaVersion":4,"pages":[]}"#.utf8), forKey: "layout")
    #expect(Dashboard.load(from: defaults) == .defaults)
}

@Test func aSavedLayoutIsTheOneThatLoads() throws {
    let defaults = scratchDefaults()
    var editing = Editing(.starter)
    editing.add(.github, size: .medium, preferring: 0)
    try editing.dashboard.save(to: defaults)
    #expect(Dashboard.load(from: defaults) == editing.dashboard)
}
