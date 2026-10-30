import CryptoKit
import Foundation

/// Everything environment-specific lives here so the feed code stays generic.
public struct Config: Sendable {
    public var place: Place

    /// Google Calendar's private "secret address" in iCal format. Treated as a
    /// bearer secret: anyone holding the URL can read the calendar.
    public var calendarICSURL: URL?

    /// A GitHub OAuth token from the device flow, a bearer secret like the address above.
    public var githubToken: String?

    /// iCloud calendars, read with the account's app-specific password.
    public var icloud: ICloudAccount?

    /// Whether the Agenda has anything to read.
    public var hasCalendar: Bool { calendarICSURL != nil || icloud?.calendars.isEmpty == false }

    /// The key a paired Mac uses on the bridge.
    public var bridgeKey: SymmetricKey?

    /// api.weather.gov requires a User-Agent identifying the app and a contact.
    /// Requests without one are rejected.
    public var userAgent: String

    /// Earthquakes count within this distance of the place.
    public var quakeRadiusKM: Double = 500

    /// Radius for the ADS-B query, nautical miles.
    public var flightRadiusNM: Int = 50

    public init(place: Place, calendarICSURL: URL?, contact: String) {
        self.place = place
        self.calendarICSURL = calendarICSURL
        self.userAgent = "Northlight/1.0 (tvOS dashboard; \(contact))"
    }
}
