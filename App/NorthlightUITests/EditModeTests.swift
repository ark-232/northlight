import XCTest

@MainActor
final class EditModeTests: XCTestCase {
    private let remote = XCUIRemote.shared

    /// Presses and gives tvOS a moment to move focus, which it does after the press.
    private func press(_ button: XCUIRemote.Button, times: Int = 1) {
        for _ in 0..<times {
            remote.press(button)
            sleep(1)
        }
    }

    /// Holds Select for the focused widget's menu, whose items tvOS shows as cells.
    private func openMenu(_ app: XCUIApplication) {
        remote.press(.select, forDuration: 2)
        XCTAssertTrue(app.cells.firstMatch.waitForExistence(timeout: 5))
        sleep(1)
    }

    func testMoveCancelResizeRemoveAndAddSurviveARelaunch() {
        let app = XCUIApplication()
        // The two-page layout, whatever an earlier run saved; the relaunch below reads the save.
        app.launchArguments = ["-settings", reykjavikSettings, "-page", "0", "-layout", starterLayout]
        app.launch()
        XCTAssertTrue(app.staticTexts["Reykjavík"].waitForExistence(timeout: 10))
        let weather = app.buttons["tile.Weather"], agenda = app.buttons["tile.Agenda"]

        // Hold Select on a widget for its menu, whose first item starts editing.
        press(.select)
        XCTAssertTrue(weather.waitForFocus(timeout: 5))
        openMenu(app)
        press(.select)
        XCTAssertTrue(app.buttons["done"].waitForExistence(timeout: 5))

        // Carry the weather to the right half and put it down there. Carried, it stays
        // on its page: Right past the last slot and Up to the header find nothing.
        press(.select)
        press(.right, times: 2)
        press(.up)
        press(.select)
        XCTAssertGreaterThan(weather.frame.minX, agenda.frame.minX)

        // Carried again, Back puts it back where it was picked up.
        press(.select)
        press(.left)
        press(.menu)
        XCTAssertGreaterThan(weather.frame.minX, agenda.frame.minX)

        // Its menu makes it medium, then removes it.
        XCTAssertTrue(weather.waitForFocus(timeout: 5))
        let tall = weather.frame.height
        openMenu(app)
        press(.select)          // Make Medium
        XCTAssertLessThan(weather.frame.height, tall * 0.75)
        XCTAssertTrue(weather.waitForFocus(timeout: 5))
        openMenu(app)
        press(.down)            // past Make Large to Remove
        press(.select)
        XCTAssertTrue(app.buttons["Remove"].waitForExistence(timeout: 5))
        press(.right)           // past Cancel, which the dialog focuses first
        press(.select)
        XCTAssertTrue(weather.waitForNonExistence(timeout: 5))

        // The gallery adds GitHub, which fits on this page now.
        press(.up)
        for _ in 0..<5 where !app.buttons["add"].waitForFocus(timeout: 2) {
            press(.right)
        }
        press(.select)
        let github = app.buttons["gallery.GitHub"]
        XCTAssertTrue(github.waitForExistence(timeout: 5))
        for _ in 0..<6 where !github.waitForFocus(timeout: 2) {
            press(app.buttons["gallery.Seismic"].hasFocus || app.buttons["gallery.Overhead"].hasFocus ? .right : .down)
        }
        press(.select)
        XCTAssertTrue(app.buttons["tile.GitHub"].waitForExistence(timeout: 5))

        // Done keeps it all, through a relaunch that reads the saved layout.
        press(.up)
        for _ in 0..<5 where !app.buttons["done"].waitForFocus(timeout: 2) {
            press(.right)
        }
        press(.select)
        app.terminate()
        app.launchArguments = ["-settings", reykjavikSettings, "-page", "0"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Agenda"].waitForExistence(timeout: 10))
        press(.select)
        XCTAssertTrue(app.buttons["tile.GitHub"].waitForExistence(timeout: 5))
        XCTAssertFalse(weather.exists)
    }

    func testTheDashboardRestsThirtySecondsAfterEditingEnds() {
        let app = XCUIApplication()
        app.launchArguments = ["-settings", reykjavikSettings, "-page", "0", "-layout", starterLayout]
        app.launch()
        XCTAssertTrue(app.staticTexts["Reykjavík"].waitForExistence(timeout: 10))
        let ambient = app.buttons["ambient"]

        press(.select)
        XCTAssertTrue(app.buttons["tile.Weather"].waitForFocus(timeout: 5))
        openMenu(app)
        press(.select)          // Edit Widgets
        XCTAssertTrue(app.buttons["done"].waitForExistence(timeout: 5))
        sleep(35)
        XCTAssertFalse(ambient.exists, "editing never rests")

        press(.menu)            // Done, with the first tile focused as it was
        XCTAssertTrue(app.buttons["done"].waitForNonExistence(timeout: 5))
        sleep(10)
        XCTAssertFalse(ambient.exists, "the time spent editing counts as input")
        XCTAssertTrue(ambient.waitForExistence(timeout: 30))
    }
}
