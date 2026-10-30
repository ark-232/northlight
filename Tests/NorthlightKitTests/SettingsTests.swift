import Foundation
import Testing
@testable import NorthlightKit

private let reykjavik = Place(name: "Reykjavík", latitude: 64.1466, longitude: -21.9426,
                              timeZoneIdentifier: "Atlantic/Reykjavik", countryCode: "IS")

private func scratchDefaults() -> UserDefaults {
    let name = "northlight-settings-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@Test func settingsSurviveARelaunch() {
    let defaults = scratchDefaults()
    Settings(place: reykjavik).save(to: defaults)
    #expect(Settings.load(from: defaults) == Settings(place: reykjavik))
}

@Test func aFreshInstallHasNoPlace() {
    #expect(Settings.load(from: scratchDefaults()).place == nil)
}

@Test func unreadableSettingsLoadAsNoPlace() {
    // An unreadable record sends the TV back to choosing a place rather than
    // rendering half a configuration.
    let defaults = scratchDefaults()
    defaults.set(Data("not json".utf8), forKey: "settings")
    #expect(Settings.load(from: defaults).place == nil)
}

@Test func nwsAlertsCoverTheUnitedStatesAndItsTerritoriesOnly() {
    for code in ["US", "PR", "GU", "VI", "AS", "MP"] {
        var place = reykjavik
        place.countryCode = code
        #expect(place.hasNWSAlerts, "\(code)")
    }
    #expect(!reykjavik.hasNWSAlerts)
    var unknown = reykjavik
    unknown.countryCode = nil
    #expect(!unknown.hasNWSAlerts)
}

@Test func theQuakeThresholdIsTheSmallestUSGSCatalogsAtThePlace() {
    for code in ["US", "PR", "VI"] {
        var place = reykjavik
        place.countryCode = code
        #expect(place.quakeMinMagnitude == 2.5, "\(code)")
    }
    for code in ["IS", "GU", "MP", "AS", nil] as [String?] {
        var place = reykjavik
        place.countryCode = code
        #expect(place.quakeMinMagnitude == 4.5, "\(code ?? "nil")")
    }
}

@Test func chosenUnitsOverrideTheTVsRegion() throws {
    let us = Locale(identifier: "en_US"), sweden = Locale(identifier: "sv_SE")
    #expect(Units.metric.locale(over: us).measurementSystem == .metric)
    #expect(Units.imperial.locale(over: sweden).measurementSystem == .us)
    // The region's other conventions stay: Swedish numbers in imperial units.
    #expect(Units.imperial.locale(over: sweden).decimalSeparator == ",")
}

@Test func settingsSavedBeforeUnitsLoadWithTheTVsOwn() throws {
    let defaults = scratchDefaults()
    defaults.set(Data(#"{"place":{"name":"Reykjavík","latitude":64.1466,"longitude":-21.9426,"timeZoneIdentifier":"Atlantic/Reykjavik","countryCode":"IS"}}"#.utf8),
                 forKey: "settings")
    let settings = Settings.load(from: defaults)
    #expect(settings.place?.name == "Reykjavík")
    #expect(settings.units == nil)
}

/// The owner's choice: other services see the place to about a kilometre.
@Test func servicesSeeThePlaceToAboutAKilometre() {
    let exact = Place(name: "Reykjavík", latitude: 64.1466, longitude: -21.9426, timeZoneIdentifier: "Atlantic/Reykjavik", countryCode: "IS")
    #expect(exact.shared.latitude == 64.15)
    #expect(exact.shared.longitude == -21.94)
    #expect(exact.shared.timeZoneIdentifier == exact.timeZoneIdentifier)
}
