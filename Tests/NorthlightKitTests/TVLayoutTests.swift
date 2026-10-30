import Foundation
import Testing
@testable import NorthlightKit

private func scratchDefaults() -> UserDefaults {
    let name = "northlight-tvlayout-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

private let start = LayoutRevision(epoch: UUID(), n: 7)
private let nearby = Dashboard(pages: [Dashboard.starter.pages[1]])!

@Test func aMacEditOfTheCurrentRevisionAppliesOnceAndBumps() {
    var layout = TVLayout(dashboard: .starter, revision: start)
    let echo = layout.receive(LayoutFrame(revision: start, base: start, dashboard: nearby), refusing: false)
    #expect(layout.dashboard == nearby)
    #expect(layout.revision == start.next)
    #expect(echo == LayoutFrame(revision: start.next, base: start, dashboard: nearby))
}

@Test func aMacEditOfAnOlderRevisionEchoesTheTVsLayout() {
    var layout = TVLayout(dashboard: .starter, revision: start)
    let stale = LayoutRevision(epoch: start.epoch, n: 6)
    let echo = layout.receive(LayoutFrame(revision: stale, base: stale, dashboard: nearby), refusing: false)
    #expect(layout.dashboard == .starter)
    #expect(echo == LayoutFrame(revision: start, base: nil, dashboard: .starter))
}

@Test func aRevisionFromAnotherInstallNeverMatches() {
    var layout = TVLayout(dashboard: .starter, revision: start)
    let other = LayoutRevision(epoch: UUID(), n: start.n)
    #expect(layout.receive(LayoutFrame(revision: other, base: other, dashboard: nearby), refusing: false).dashboard == .starter)
}

@Test func aTVBusyEditingRefusesTheMacsLayout() {
    var layout = TVLayout(dashboard: .starter, revision: start)
    let echo = layout.receive(LayoutFrame(revision: start, base: start, dashboard: nearby), refusing: true)
    #expect(layout.dashboard == .starter)
    #expect(echo.base == nil)
}

@Test func anEditOnTheTVBumpsSoTheMacsBaseGoesStale() {
    var layout = TVLayout(dashboard: .starter, revision: start)
    layout.dashboard = .starter
    #expect(layout.revision == start)
    layout.dashboard = nearby
    #expect(layout.revision == start.next)
    let echo = layout.receive(LayoutFrame(revision: start, base: start, dashboard: .starter), refusing: false)
    #expect(echo.dashboard == nearby)
}

@Test func theLayoutAndItsRevisionAreKeptTogether() throws {
    let defaults = scratchDefaults()
    let first = TVLayout.load(from: defaults)
    #expect(first.dashboard == .defaults)
    #expect(first.revision.n == 0)
    // Each install draws its own epoch.
    #expect(TVLayout.load(from: scratchDefaults()).revision.epoch != first.revision.epoch)

    var changed = first
    changed.dashboard = nearby
    try changed.save(to: defaults)
    #expect(TVLayout.load(from: defaults) == changed)
}

@Test func aLayoutKeptBeforeRevisionsLoadsWithANewEpoch() throws {
    let defaults = scratchDefaults()
    try nearby.save(to: defaults)
    let loaded = TVLayout.load(from: defaults)
    #expect(loaded.dashboard == nearby)
    #expect(loaded.revision.n == 0)
}
