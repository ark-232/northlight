import XCTest

/// Reykjavík as stored Settings JSON, injected through the arguments domain.
let reykjavikSettings = "<7b22706c616365223a7b226e616d65223a225265796b6a6176c3ad6b222c226c61746974756465223a36342e313436362c226c6f6e676974756465223a2d32312e393432362c2274696d655a6f6e654964656e746966696572223a2241746c616e7469635c2f5265796b6a6176696b222c22636f756e747279436f6465223a224953227d7d>"

/// The two-page layout these tests walk: Today with weather L, agenda M, aurora and
/// daylight S; Nearby with aircraft L, seismic M, air and snow S.
let starterLayout: String = {
    func placement(_ id: Int, _ kind: String, _ size: String) -> String {
        #"{"id":"00000000-0000-4000-8000-00000000000\#(id)","config":{"\#(kind)":\#(kind == "seismic" ? #"{"minMagnitude":2.5}"# : "{}")},"size":"\#(size)"}"#
    }
    let json = #"{"schemaVersion":3,"pages":[{"id":"00000000-0000-4000-8000-0000000000a1","name":"Today","placements":["#
        + [placement(1, "weather", "large"), placement(2, "agenda", "medium"), placement(3, "aurora", "small"),
           placement(4, "daylight", "small")].joined(separator: ",")
        + #"]},{"id":"00000000-0000-4000-8000-0000000000a2","name":"Nearby","placements":["#
        + [placement(5, "flights", "large"), placement(6, "seismic", "medium"), placement(7, "airSnow", "small")].joined(separator: ",")
        + "]}]}"
    return "<" + Data(json.utf8).map { String(format: "%02x", $0) }.joined() + ">"
}()

extension XCUIElement {
    /// Focus moves after the frame that shows the element, so it is waited for.
    func waitForFocus(timeout: TimeInterval) -> Bool {
        let focused = XCTNSPredicateExpectation(predicate: NSPredicate(format: "hasFocus == true"), object: self)
        return XCTWaiter.wait(for: [focused], timeout: timeout) == .completed
    }
}

extension XCUIApplication {
    /// From a layout that opens on the weather, at rest, up to the header and across to Settings.
    func openSettings() {
        let remote = XCUIRemote.shared
        remote.press(.select)   // browse
        _ = buttons["tile.Weather"].waitForFocus(timeout: 5)
        remote.press(.up)       // the header, at the first page's chip
        for _ in 0..<5 where !buttons["Settings"].waitForFocus(timeout: 1) {
            remote.press(.right)
        }
        remote.press(.select)
    }
}

@MainActor
final class BrowseTests: XCTestCase {
    func testPagesDetailAndTheWayBack() {
        let app = XCUIApplication()
        app.launchArguments = ["-settings", reykjavikSettings, "-page", "0", "-layout", starterLayout]
        app.launch()
        let remote = XCUIRemote.shared
        XCTAssertTrue(app.staticTexts["Reykjavík"].waitForExistence(timeout: 10))

        // At rest nothing is focused; the first click focuses the first tile.
        let weather = app.buttons["tile.Weather"]
        XCTAssertFalse(weather.exists)
        remote.press(.select)
        XCTAssertTrue(weather.waitForExistence(timeout: 5))
        XCTAssertTrue(weather.waitForFocus(timeout: 5))

        // Past the last column is the next page.
        let overhead = app.buttons["tile.Overhead"]
        for _ in 0..<4 where !overhead.exists {
            remote.press(.right)
        }
        XCTAssertTrue(overhead.waitForExistence(timeout: 5))
        XCTAssertFalse(weather.exists)

        // Up lands on the page's own chip, and the first page's chip brings it back.
        remote.press(.up)
        XCTAssertTrue(app.buttons["Nearby"].waitForFocus(timeout: 5))
        remote.press(.left)
        XCTAssertTrue(app.buttons["Today"].waitForFocus(timeout: 5))
        XCTAssertFalse(weather.exists)
        remote.press(.select)
        XCTAssertTrue(weather.waitForExistence(timeout: 5))

        // Select opens a widget; Back closes it, Back again rests, and Back once more leaves.
        remote.press(.down)
        remote.press(.select)
        let detail = app.otherElements["detail"]
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        remote.press(.menu)
        XCTAssertTrue(detail.waitForNonExistence(timeout: 5))
        remote.press(.menu)
        XCTAssertTrue(weather.waitForNonExistence(timeout: 5))
        remote.press(.menu)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
    }

    /// At rest the remote turns pages with nothing focused, and up starts browsing there.
    func testRestTurnsPagesWithoutFocus() {
        let app = XCUIApplication()
        app.launchArguments = ["-settings", reykjavikSettings, "-page", "0", "-layout", starterLayout]
        app.launch()
        let remote = XCUIRemote.shared
        XCTAssertTrue(app.staticTexts["Reykjavík"].waitForExistence(timeout: 10))
        func dots(_ page: Int) -> XCUIElement {
            app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Page \(page) of 2")).firstMatch
        }
        XCTAssertTrue(dots(1).exists)

        remote.press(.right)
        XCTAssertTrue(dots(2).waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tile.Overhead"].exists)
        remote.press(.right)    // the last page holds
        remote.press(.left)
        XCTAssertTrue(dots(1).waitForExistence(timeout: 5))
        remote.press(.right)
        XCTAssertTrue(dots(2).waitForExistence(timeout: 5))

        remote.press(.up)
        XCTAssertTrue(app.buttons["tile.Overhead"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["tile.Weather"].exists)
    }
}
