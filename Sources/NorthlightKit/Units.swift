import Foundation

// The locale picks each unit: the region's custom, or the measurement system the
// owner chose. Feeds stay metric.

/// "-4°" or "25°", with the scale left unnamed. A reading that rounds to zero
/// reads "0°", never "-0°".
public struct TemperatureFormat: FormatStyle {
    var locale = Locale.autoupdatingCurrent

    public func format(_ value: Measurement<UnitTemperature>) -> String {
        let unit = UnitTemperature(forLocale: locale, usage: .weather)
        let degrees = value.converted(to: unit).value.rounded()
        return Measurement(value: degrees == 0 ? 0 : degrees, unit: unit).formatted(
            .measurement(width: .narrow, usage: .asProvided, hidesScaleName: true,
                         numberFormatStyle: .number.precision(.fractionLength(0))).locale(locale))
    }

    public func locale(_ locale: Locale) -> Self {
        Self(locale: locale)
    }
}

extension FormatStyle where Self == TemperatureFormat {
    public static var temperature: Self { TemperatureFormat() }
}

extension FormatStyle where Self == Measurement<UnitSpeed>.FormatStyle {
    /// "26 km/h", "16 mph" or "7 m/s".
    public static var wind: Self {
        .measurement(width: .abbreviated, usage: .wind, numberFormatStyle: .number.precision(.fractionLength(0)))
    }
}

extension Measurement where UnitType == UnitLength {
    /// Whether `.snow` shows this as more than nothing: at least a tenth of the
    /// locale's unit.
    public func showsAsSnow(in locale: Locale) -> Bool {
        (converted(to: UnitLength(forLocale: locale, usage: .snowfall)).value * 10).rounded() >= 1
    }
}

extension FormatStyle where Self == Measurement<UnitLength>.FormatStyle {
    /// Snow on the ground or falling: "8 cm" or "3.1 in".
    public static var snow: Self {
        .measurement(width: .abbreviated, usage: .snowfall, numberFormatStyle: .number.precision(.fractionLength(0...1)))
    }
}
