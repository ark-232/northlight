import Foundation
import Testing
@testable import NorthlightKit

/// CISA's Known Exploited Vulnerabilities catalog of 16 Oct 2026, cut to its eight
/// newest entries; `count` is still the whole catalog's.

@Test func theCatalogKeepsItsCountAndNewestEntries() throws {
    let catalog = try KEVParsing.catalog(from: fixture("kev"), now: utc("2026-10-20T04:00:00Z"))
    #expect(catalog.count == 1_748)
    #expect(catalog.recent.count == 8)
    let newest = try #require(catalog.recent.first)
    #expect(newest == KEVEntry(cve: "CVE-2026-102764", vendor: "BeyondTrust", product: "Remote Support", added: utc("2026-10-16T00:00:00Z")))
    #expect(catalog.recent.map(\.added) == catalog.recent.map(\.added).sorted(by: >))
}

@Test func thisWeekIsTheLastSevenDaysCountingToday() throws {
    let catalog = try KEVParsing.catalog(from: fixture("kev"), now: utc("2026-10-20T04:00:00Z"))
    #expect(catalog.addedThisWeek(at: utc("2026-10-20T04:00:00Z")) == 7)
    #expect(catalog.addedThisWeek(at: utc("2026-10-22T12:00:00Z")) == 2)
}

@Test func entriesOlderThanAMonthAreNotKept() throws {
    let json = #"{"count":2,"vulnerabilities":[{"cveID":"CVE-2026-1","vendorProject":"A","product":"B","dateAdded":"2026-10-19"},{"cveID":"CVE-2021-1","vendorProject":"C","product":"D","dateAdded":"2021-11-03"}]}"#
    let catalog = try KEVParsing.catalog(from: Data(json.utf8), now: utc("2026-10-20T04:00:00Z"))
    #expect(catalog.count == 2)
    #expect(catalog.recent.map(\.cve) == ["CVE-2026-1"])
}
