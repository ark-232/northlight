import XCTest

/// Needs the simulator's location and permission set first:
///   xcrun simctl location booted set 64.1466,-21.9426
///   xcrun simctl privacy booted grant location com.arkwerx.northlight
@MainActor
final class SettingsTests: XCTestCase {
    func testTheTVsLocationSetsThePlace() {
        let app = XCUIApplication()
        // A string in the arguments domain reads as no saved settings: a first run.
        app.launchArguments = ["-settings", "none", "-page", "0", "-layout", "none"]
        app.launch()

        XCTAssertTrue(app.buttons["Use this Apple TV's location"].waitForExistence(timeout: 5))
        XCUIRemote.shared.press(.select)

        // The dashboard replaces the first-run screen, its weather tile named for the place.
        XCTAssertTrue(app.staticTexts["Reykjavík"].waitForExistence(timeout: 20),
                      "the screen read: \(app.staticTexts.allElementsBoundByIndex.map(\.label))")
    }
}

@MainActor
final class CalendarSettingsTests: XCTestCase {
    private let holidays = "https://calendar.google.com/calendar/ical/en.usa%23holiday%40group.v.calendar.google.com/public/basic.ics"

    func testACalendarAddressIsKeptMaskedAndRemoved() {
        let app = XCUIApplication()
        app.launchArguments = ["-settings", reykjavikSettings, "-page", "0", "-layout", "none"]
        app.launch()
        let remote = XCUIRemote.shared

        XCTAssertTrue(app.staticTexts["Reykjavík"].waitForExistence(timeout: 10))
        app.openSettings()
        let field = app.secureTextFields["Paste a calendar's .ics address"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        for _ in 0..<5 where !field.waitForFocus(timeout: 2) {
            remote.press(.down)
        }
        remote.press(.select)   // keyboard
        app.typeText(holidays)
        remote.press(.menu)     // close the keyboard; the text stays in the field
        RunLoop.current.run(until: Date().addingTimeInterval(1))
        XCTAssertTrue(app.buttons["Save address"].waitForExistence(timeout: 5))
        remote.press(.down)     // Save address
        remote.press(.select)

        let summary = app.staticTexts["calendar.google.com, \(holidays.count) characters"]
        XCTAssertTrue(summary.waitForExistence(timeout: 10))
        let noCalendar = app.staticTexts["No calendar set"]

        remote.press(.menu)     // back to the dashboard
        remote.press(.menu)     // at rest, where the tiles read as text and the agenda reads the calendar
        XCTAssertTrue(app.staticTexts["Reykjavík"].waitForExistence(timeout: 5))
        XCTAssertFalse(noCalendar.exists)

        // The address outlives the app.
        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["Reykjavík"].waitForExistence(timeout: 10))
        XCTAssertFalse(noCalendar.exists)

        app.openSettings()
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        for _ in 0..<5 where !field.waitForFocus(timeout: 2) {
            remote.press(.down)
        }
        remote.press(.down)     // Remove calendar
        remote.press(.select)
        XCTAssertTrue(app.staticTexts["Not set"].waitForExistence(timeout: 5))

        remote.press(.menu)     // back to the dashboard
        remote.press(.menu)     // at rest
        XCTAssertTrue(noCalendar.waitForExistence(timeout: 5))

        // So does its removal.
        app.terminate()
        app.launch()
        XCTAssertTrue(noCalendar.waitForExistence(timeout: 10))
    }
}

@MainActor
final class PlaceSearchTests: XCTestCase {
    func testSearchingForAPlaceSetsIt() {
        let app = XCUIApplication()
        app.launchArguments = ["-settings", "none", "-page", "0", "-layout", "none"]
        app.launch()
        let remote = XCUIRemote.shared

        let field = app.textFields["Search for a place"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        for _ in 0..<3 where !field.waitForFocus(timeout: 2) {
            remote.press(.down)
        }
        remote.press(.select)   // keyboard
        app.typeText("Reykjavik")
        remote.press(.menu)     // close the keyboard
        let result = app.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Reykjavík'")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15))
        for _ in 0..<3 where !result.waitForFocus(timeout: 2) {
            remote.press(.down)
        }
        remote.press(.select)

        // The dashboard replaces the first-run screen, its weather tile named for the place.
        XCTAssertTrue(app.buttons["ambient"].waitForExistence(timeout: 20))
        XCTAssertTrue(app.staticTexts["Reykjavík"].exists)
    }
}

@MainActor
final class UnitsTests: XCTestCase {
    /// The simulator's region is the US, where wind reads in mph.
    func testMetricWinsOverTheRegion() {
        let app = XCUIApplication()
        app.launchArguments = ["-settings", reykjavikSettings, "-page", "0", "-layout", "none"]
        app.launch()
        let remote = XCUIRemote.shared
        func wind(_ unit: String) -> XCUIElement {
            app.staticTexts.matching(NSPredicate(format: "label ENDSWITH %@", " \(unit)")).firstMatch
        }
        XCTAssertTrue(wind("mph").waitForExistence(timeout: 30), "the weather loads, in the region's units")

        app.openSettings()
        let metric = app.buttons["Metric"]
        XCTAssertTrue(metric.waitForExistence(timeout: 5))
        for _ in 0..<4 where !app.buttons["Automatic"].waitForFocus(timeout: 2) {
            remote.press(.down)
        }
        remote.press(.right)
        XCTAssertTrue(metric.waitForFocus(timeout: 5))
        remote.press(.select)
        remote.press(.menu)     // back to the dashboard
        remote.press(.menu)     // at rest, where the tiles read as text
        XCTAssertTrue(wind("km/h").waitForExistence(timeout: 10))
    }
}

@MainActor
final class AboutTests: XCTestCase {
    func testAboutCreditsEveryDataSource() {
        let app = XCUIApplication()
        app.launchArguments = ["-settings", reykjavikSettings, "-page", "0", "-layout", "none"]
        app.launch()
        let remote = XCUIRemote.shared
        XCTAssertTrue(app.staticTexts["Reykjavík"].waitForExistence(timeout: 10))

        app.openSettings()
        let about = app.buttons["About Northlight"]
        XCTAssertTrue(about.waitForExistence(timeout: 5))
        for _ in 0..<12 where !about.waitForFocus(timeout: 2) {
            remote.press(.down)
        }
        remote.press(.select)
        for source in ["Open-Meteo", "CC BY 4.0", "Copernicus Atmosphere Monitoring Service", "National Weather Service",
                       "adsb.fi", "U.S. Geological Survey", "NOAA Space Weather Prediction Center", "wheretheiss.at",
                       "The Space Devs", "Hacker News", "GitHub Status", "Claude Status", "CC0", "Kraken", "Frankfurter",
                       "Apple Maps"] {
            let credit = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", source)).firstMatch
            XCTAssertTrue(credit.waitForExistence(timeout: 5), source)
        }
    }
}
