import XCTest

@MainActor
final class NetworkTests: XCTestCase {
    /// One page with the Network widget first, so the first click focuses it.
    private let networkLayout: String = {
        let json = #"{"schemaVersion":1,"pages":[{"id":"6A1E3C1F-6D1B-4E7A-9B57-0B3C0E2C4A11","name":"Today","placements":[{"id":"0F4B0F7E-3E1C-4C0A-8E44-5A0F2C3B6D21","config":{"network":{}},"size":"medium"},{"id":"9C2D1A7B-6F3E-4B8C-A1D5-2E7F9B0C3A31","config":{"weather":{}},"size":"medium"}]}]}"#
        return "<" + Data(json.utf8).map { String(format: "%02x", $0) }.joined() + ">"
    }()

    /// M-Lab publishes each tester's IP address, so nothing runs before the viewer agrees.
    func testASpeedTestAsksFirstAndNotNowRunsNothing() {
        let app = XCUIApplication()
        app.launchArguments = ["-settings", reykjavikSettings, "-page", "0", "-layout", networkLayout,
                               "-speedTestConsent", "NO"]
        app.launch()
        let remote = XCUIRemote.shared
        XCTAssertTrue(app.staticTexts["Reykjavík"].waitForExistence(timeout: 10))

        remote.press(.select)   // browse, on the Network widget
        XCTAssertTrue(app.buttons["tile.Network"].waitForFocus(timeout: 5))
        remote.press(.select)   // its detail
        let run = app.buttons["Run speed test"]
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        XCTAssertTrue(run.waitForFocus(timeout: 5))
        remote.press(.select)

        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS 'public IP address'")).firstMatch
            .waitForExistence(timeout: 5))
        let notNow = app.buttons["Not now"]
        XCTAssertTrue(notNow.waitForFocus(timeout: 5), "declining is the default")
        remote.press(.select)

        XCTAssertTrue(notNow.waitForNonExistence(timeout: 5))
        XCTAssertTrue(run.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Testing"].exists)
    }
}
