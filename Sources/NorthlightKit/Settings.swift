import Foundation

/// Where the dashboard is. Every feed and clock describes this place.
public struct Place: Codable, Sendable, Hashable {
    /// The place as other services see it: to two decimal places of a degree, about a
    /// kilometre, the owner's choice.
    public var shared: Place {
        var place = self
        place.latitude = (latitude * 100).rounded() / 100
        place.longitude = (longitude * 100).rounded() / 100
        return place
    }

    public var name: String
    public var latitude: Double
    public var longitude: Double
    /// The place's time zone, from the geocoder.
    public var timeZoneIdentifier: String
    /// ISO 3166-1 alpha-2, from the geocoder.
    public var countryCode: String?

    public init(name: String, latitude: Double, longitude: Double, timeZoneIdentifier: String, countryCode: String?) {
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.timeZoneIdentifier = timeZoneIdentifier
        self.countryCode = countryCode
    }

    /// The one clock the dashboard keeps. A zone that later drops out of the
    /// system's database reads as UTC rather than stopping the display.
    public var timeZone: TimeZone {
        TimeZone(identifier: timeZoneIdentifier) ?? .gmt
    }

    public var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    /// NWS issues alerts for the United States and its territories only.
    public var hasNWSAlerts: Bool {
        guard let countryCode else { return false }
        return ["US", "PR", "GU", "VI", "AS", "MP"].contains(countryCode)
    }

    /// USGS lists quakes from M2.5 where an ANSS regional network reports (the
    /// United States, Puerto Rico and the US Virgin Islands) and from about M4.5
    /// everywhere else, so a quiet week is claimed only down to what it catalogs.
    public var quakeMinMagnitude: Double {
        guard let countryCode, ["US", "PR", "VI"].contains(countryCode) else { return 4.5 }
        return 2.5
    }
}

/// Units chosen over the ones the TV's region uses.
public enum Units: String, Codable, Sendable, CaseIterable {
    case metric, imperial

    /// `base` with this choice's units and the rest of its conventions.
    public func locale(over base: Locale) -> Locale {
        var components = Locale.Components(locale: base)
        components.measurementSystem = self == .metric ? .metric : .us
        return Locale(components: components)
    }
}

/// The owner's choices, kept in UserDefaults on the TV.
public struct Settings: Codable, Sendable, Equatable {
    public var place: Place?
    /// Nil reads in the units of the TV's region.
    public var units: Units?

    public init(place: Place? = nil, units: Units? = nil) {
        self.place = place
        self.units = units
    }

    static let defaultsKey = "settings"

    /// A missing or unreadable record loads as no place, which sends the TV back
    /// to choosing one rather than rendering half a configuration.
    public static func load(from defaults: UserDefaults) -> Settings {
        guard let data = defaults.data(forKey: defaultsKey),
              let settings = try? JSONDecoder().decode(Settings.self, from: data)
        else { return Settings() }
        return settings
    }

    public func save(to defaults: UserDefaults) {
        // Strings and the finite coordinates CoreLocation reports always encode.
        defaults.set(try! JSONEncoder().encode(self), forKey: Self.defaultsKey)
    }
}
