import Foundation
import Testing
@testable import NorthlightKit

/// An Open-Meteo response from 19 October 2026, in the API's default
/// units: °C, km/h, snowfall in centimetres and snow depth in metres.
private func recorded() throws -> Weather {
    let url = try #require(Bundle.module.url(forResource: "open-meteo", withExtension: "json", subdirectory: "Fixtures"))
    return try WeatherParsing.weather(from: Data(contentsOf: url), timeZone: TimeZone(identifier: "Atlantic/Reykjavik")!)
}

@Test func theWeatherKeepsTheUnitsOpenMeteoSends() throws {
    let weather = try recorded()
    #expect(weather.temperature == Measurement(value: -3.7, unit: .celsius))
    #expect(weather.apparent == Measurement(value: -10.5, unit: .celsius))
    #expect(weather.windSpeed == Measurement(value: 25.9, unit: .kilometersPerHour))
    #expect(weather.snowDepth == Measurement(value: 0.08, unit: .meters))
    let today = try #require(weather.days.first)
    #expect(today.high == Measurement(value: -3.5, unit: .celsius))
    #expect(today.low == Measurement(value: -11.1, unit: .celsius))
    #expect(today.snowfall == Measurement(value: 0.28, unit: .centimeters))
}

private func expectReadings(in locale: Locale, _ temperature: String, _ wind: String, _ snow: String) throws {
    let weather = try recorded()
    let depth = try #require(weather.snowDepth)
    #expect(weather.temperature.formatted(.temperature.locale(locale)) == temperature)
    #expect(weather.windSpeed.formatted(.wind.locale(locale)) == wind)
    #expect(depth.formatted(.snow.locale(locale)) == snow)
}

// The United Kingdom gives wind in miles per hour and snow in centimetres, so
// the units follow the region, not one metric-or-imperial switch.
private let regions: [(String, String, String, String)] = [
    ("en_US", "25°", "16 mph", "3.1 in"),
    ("en_GB", "-4°", "16 mph", "8 cm"),
    ("de_DE", "-4°", "26 km/h", "8 cm"),
    // Sweden writes a true minus sign and gives wind in metres per second.
    ("sv_SE", "\u{2212}4°", "7 m/s", "8 cm"),
]

@Test(arguments: regions)
func eachRegionReadsTheWeatherInItsOwnUnits(locale: String, temperature: String, wind: String, snow: String) throws {
    try expectReadings(in: Locale(identifier: locale), temperature, wind, snow)
}

@Test func aChosenMeasurementSystemOverridesTheRegion() throws {
    var components = Locale.Components(locale: Locale(identifier: "en_US"))
    components.measurementSystem = .metric
    try expectReadings(in: Locale(components: components), "-4°", "26 km/h", "8 cm")
}

// -0.3 °C, and -17.9 °C, which is -0.2 °F.
private let nearZero: [(String, Double)] = [("de_DE", -0.3), ("en_US", -17.9)]

@Test(arguments: nearZero)
func aTemperatureThatRoundsToZeroReadsZero(locale: String, celsius: Double) {
    let reading = Measurement(value: celsius, unit: UnitTemperature.celsius)
    #expect(reading.formatted(.temperature.locale(Locale(identifier: locale))) == "0°")
}

// Snow shows only when it reads as at least a tenth of the locale's unit: 0.1 cm
// reads "0.1 cm" in Germany but would read "0 in" in the US.
private let traces: [(Double, String, Bool)] = [(0.1, "en_US", false), (0.1, "de_DE", true), (0.3, "en_US", true)]

@Test(arguments: traces)
func snowShowsOnlyWhenItReadsAsSomething(centimeters: Double, locale: String, shows: Bool) {
    #expect(Measurement(value: centimeters, unit: UnitLength.centimeters).showsAsSnow(in: Locale(identifier: locale)) == shows)
}
