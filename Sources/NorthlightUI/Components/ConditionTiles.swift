import SwiftUI
import NorthlightKit

/// Daylight length and its day-over-day change, plus the moon. At 61°N the change
/// is the number worth showing — it runs to five or six minutes a day near the
/// equinoxes, which is what makes the season feel like it is moving.
struct DaylightTile: View {
    let place: Place
    let now: Date
    @Environment(\.calendar) private var calendar
    @Environment(\.widgetSize) private var size

    private var moon: Moon { Moon(date: now) }

    private var clockTime: Date.FormatStyle {
        Date.FormatStyle(date: .omitted, time: .shortened, timeZone: calendar.timeZone)
    }

    private func day(containing date: Date) -> Solar.Day {
        Solar.day(containing: date, latitude: place.latitude, longitude: place.longitude, calendar: calendar)
    }

    var body: some View {
        let today = day(containing: now)
        let yesterday = day(containing: calendar.date(byAdding: .day, value: -1, to: now)!)

        Tile(label: "Daylight", accent: Theme.Palette.amber) {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    // Two band-2 values will not sit side by side in a small widget.
                    VStack(alignment: .leading, spacing: 4) {
                        Text(today.length.hoursMinutes)
                            .font(Theme.Font.tileValue)
                            .foregroundStyle(Theme.Palette.bone)
                            .lineLimit(1)
                        switch today {
                        case .risesAndSets:
                            let change = today.length - yesterday.length
                            Text("\(change.signedMinutesSeconds) today")
                                .font(Theme.Font.body)
                                .foregroundStyle(change < 0 ? Theme.Palette.amber : Theme.Palette.green)
                                .lineLimit(1)
                        case .alwaysUp:
                            Text("Sun up all day")
                                .font(Theme.Font.body)
                                .foregroundStyle(Theme.Palette.green)
                                .lineLimit(1)
                        case .alwaysDown:
                            Text("Sun down all day")
                                .font(Theme.Font.body)
                                .foregroundStyle(Theme.Palette.amber)
                                .lineLimit(1)
                        }
                    }
                    Spacer(minLength: 24)
                    if size == .medium, case .risesAndSets(let sunrise, let sunset) = today {
                        VStack(alignment: .trailing, spacing: 10) {
                            Label { Text(sunrise, format: clockTime) } icon: { Image(systemName: "sunrise.fill") }
                            Label { Text(sunset, format: clockTime) } icon: { Image(systemName: "sunset.fill") }
                        }
                        .font(Theme.Font.body)
                        .foregroundStyle(Theme.Palette.bone)
                    }
                }

                HStack(spacing: 12) {
                    Image(systemName: moon.symbol)
                        .font(.system(size: 30))
                        .foregroundStyle(Theme.Palette.bone)
                    Text(moon.name)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.muted)
                    Text("\(Int((moon.illumination * 100).rounded()))%")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.faint)
                }

                if size == .small, case .risesAndSets(_, let sunset) = today {
                    Text("dark from \(sunset, format: clockTime)")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.faint)
                }
            }
        }
    }
}

/// Snow and air quality share a tile because in northern places they are seasonal
/// opposites — one matters in winter, the other during summer smoke.
struct SnowAirTile: View {
    let weather: Loaded<Weather>
    let air: Loaded<AirQuality>
    let now: Date
    @Environment(\.widgetSize) private var size
    @Environment(\.locale) private var locale

    private func aqiColor(_ rank: Int) -> Color {
        switch rank {
        case 0: return Theme.Palette.green
        case 1: return Theme.Palette.amber
        case 2, 3: return Theme.Palette.red
        default: return Theme.Palette.violet
        }
    }

    var body: some View {
        Tile(label: "Air & snow", accent: Theme.Palette.cyan, trailing: air.trailing(asOf: now)) {
            VStack(alignment: .leading, spacing: 14) {
                FeedBody(state: air.state(asOf: now)) { air in
                    if let aqi = air.usAQI {
                        HStack(alignment: .firstTextBaseline, spacing: 14) {
                            Text("AQI \(aqi)")
                                .font(Theme.Font.tileValue)
                                .foregroundStyle(aqiColor(air.band.rank))
                                .numericChange(aqi)
                            Text(air.band.label)
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.muted)
                                .lineLimit(1)
                        }
                    } else {
                        TilePlaceholder(text: "No AQI reported")
                    }
                }

                if case .ready(let weather) = weather.state(asOf: now) {
                    let lines = size == .small ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 28))
                    let depth = weather.snowDepth.flatMap { $0.showsAsSnow(in: locale) ? $0 : nil }
                    let soon = weather.days.prefix(2).reduce(Measurement(value: 0, unit: UnitLength.centimeters)) { $0 + $1.snowfall }
                    lines {
                        if let depth {
                            Label("\(depth, format: .snow) base", systemImage: "snowflake")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.bone)
                        }
                        if soon.showsAsSnow(in: locale) {
                            Label("\(soon, format: .snow) coming", systemImage: "cloud.snow")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.cyan)
                        } else if depth == nil {
                            Text("No snow")
                                .font(Theme.Font.caption)
                                .foregroundStyle(Theme.Palette.faint)
                        }
                    }
                }
            }
        }
    }
}
