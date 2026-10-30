import Foundation
import Testing
@testable import NorthlightKit

/// A real iCloud account, read the way the TV reads it. It prints counts only:
///   ICLOUD_APPLE_ID=… ICLOUD_APP_PASSWORD=… swift test --filter CalDAVLive
struct CalDAVLiveTests {
    private static let environment = ProcessInfo.processInfo.environment

    @Test(.enabled(if: environment["ICLOUD_APPLE_ID"]?.isEmpty == false && environment["ICLOUD_APP_PASSWORD"]?.isEmpty == false),
          .timeLimit(.minutes(1)))
    func aLiveAccountListsItsCalendarsAndReadsTheirEvents() async throws {
        let appleID = Self.environment["ICLOUD_APPLE_ID"]!, password = Self.environment["ICLOUD_APP_PASSWORD"]!
        let http = HTTP(userAgent: "Northlight/0.1.0 (swift test)")
        let calendars = try await http.icloudCalendars(appleID: appleID, password: password)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = .gmt
        let events = try await http.icloudEvents(ICloudAccount(appleID: appleID, password: password, calendars: calendars),
                                                 window: try .agenda(calendar: utc), calendar: utc)
        print("iCloud: \(calendars.count) event calendars, \(events.count) events in the next two weeks")
        #expect(!calendars.isEmpty)
    }
}
