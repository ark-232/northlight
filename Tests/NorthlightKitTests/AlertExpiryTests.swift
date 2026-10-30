import Foundation
import Testing
@testable import NorthlightKit

private let now = Date(timeIntervalSince1970: 1_792_000_000)

private func alert(ends: TimeInterval?, expires: TimeInterval?) -> WeatherAlert {
    WeatherAlert(id: "a", event: "Winter Storm Warning", headline: nil, severity: "Severe",
                 ends: ends.map { now.addingTimeInterval($0) },
                 expires: expires.map { now.addingTimeInterval($0) })
}

@Test func anAlertIsOverWhenItsHazardEnds() {
    #expect(!alert(ends: -60, expires: 3_600).isActive(at: now))
    #expect(alert(ends: 60, expires: -3_600).isActive(at: now))
}

@Test func withoutAnEndTheMessageExpiryBoundsTheAlert() {
    // NWS often leaves `ends` null; `expires` is always present.
    #expect(!alert(ends: nil, expires: -1).isActive(at: now))
    #expect(alert(ends: nil, expires: 1).isActive(at: now))
}

@Test func anAlertWithNoTimesStaysActive() {
    #expect(alert(ends: nil, expires: nil).isActive(at: now))
}

@Test func aCachedAlertFromBeforeExpiresDecodes() throws {
    // Alerts cached by an older build carry no `expires` field.
    let json = Data(#"{"id":"a","event":"Wind Advisory","severity":"Moderate"}"#.utf8)
    let decoded = try JSONDecoder().decode(WeatherAlert.self, from: json)
    #expect(decoded.expires == nil)
    #expect(decoded.isActive(at: now))
}

@Test func nwsAlertsDecodeEndsAndExpires() throws {
    let json = Data("""
        {"features": [
          {"id": "urn:2", "properties": {"event": "Wind Advisory", "severity": "Moderate",
            "ends": "2026-10-19T12:00:00-08:00", "expires": "2026-10-19T04:00:00-08:00"}},
          {"id": "urn:1", "properties": {"event": "Winter Storm Warning", "severity": "Severe",
            "headline": "Heavy snow", "ends": null, "expires": "2026-10-19T03:00:00-08:00"}}
        ]}
        """.utf8)
    let alerts = try AlertParsing.alerts(from: json)
    #expect(alerts.map(\.event) == ["Winter Storm Warning", "Wind Advisory"])
    #expect(alerts[0].ends == nil)
    #expect(alerts[0].expires == ISO8601DateFormatter().date(from: "2026-10-19T11:00:00Z"))
    #expect(alerts[1].ends == ISO8601DateFormatter().date(from: "2026-10-19T20:00:00Z"))
}
