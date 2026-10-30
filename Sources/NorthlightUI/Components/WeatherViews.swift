import SwiftUI
import NorthlightKit

struct WeatherHero: View {
    let feed: Loaded<Weather>
    let place: String
    let now: Date
    @Environment(\.widgetSize) private var size

    var body: some View {
        Tile(label: place, accent: Theme.Palette.cyan, trailing: feed.trailing(asOf: now)) {
            FeedBody(state: feed.state(asOf: now)) { weather in
                let condition = weather.condition
                let large = size == .large
                VStack(alignment: .leading, spacing: 18) {
                    HStack(alignment: .center, spacing: 28) {
                        Text(weather.temperature, format: .temperature)
                            .font(large ? Theme.Font.heroLarge : Theme.Font.hero)
                            .foregroundStyle(Theme.Palette.bone)
                            .numericChange(weather.temperature)
                        Image(systemName: condition.symbol)
                            .font(.system(size: large ? 140 : 96))
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(Theme.Palette.cyan)
                    }
                    Text(condition.label)
                        .font(Theme.Font.title)
                        .foregroundStyle(Theme.Palette.bone)

                    HStack(spacing: 36) {
                        Metric(icon: "thermometer.medium", text: Text("feels \(weather.apparent, format: .temperature)"))
                        Metric(icon: "wind", text: Text(weather.windSpeed, format: .wind))
                        Metric(icon: "humidity", text: Text(verbatim: "\(weather.humidity)%"))
                    }

                    // Sunrise and sunset live in the Daylight widget.
                    if large {
                        Spacer(minLength: 0)
                        ForecastStrip(days: weather.days)
                            .frame(height: 240)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .layoutPriority(1)
            }
        }
    }

    private struct Metric: View {
        let icon: String
        let text: Text
        var body: some View {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.Palette.faint)
                text
                    .font(Theme.Font.bodySmall)
                    .foregroundStyle(Theme.Palette.muted)
            }
        }
    }
}

struct ForecastStrip: View {
    let days: [Weather.Day]
    @Environment(\.timeZone) private var zone

    var body: some View {
        HStack(spacing: Theme.Metric.tileSpacing) {
            ForEach(Array(days.dropFirst().prefix(5))) { day in
                VStack(spacing: 6) {
                    Text(day.date.formatted(Date.FormatStyle(timeZone: zone).weekday(.abbreviated)))
                        .font(Theme.Font.label)
                        .foregroundStyle(Theme.Palette.muted)
                    Image(systemName: Weather.describe(day.code, isDay: true).symbol)
                        .font(.system(size: 30))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.Palette.bone)
                    // The cell is about 88 pt wide, so these shrink rather than
                    // ellipsise when a temperature needs three glyphs.
                    HStack(spacing: 6) {
                        Text(day.high, format: .temperature)
                            .foregroundStyle(Theme.Palette.bone)
                        Text(day.low, format: .temperature)
                            .foregroundStyle(Theme.Palette.faint)
                    }
                    .font(.system(size: 23, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    // Always rendered, so every cell is the same height — a
                    // conditional row here makes the strip ragged.
                    Text(day.precipitationChance >= 20 ? "\(day.precipitationChance)%" : " ")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.cyan)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Theme.Palette.surface)
                )
            }
        }
    }
}

/// The coming days as rows, for a large forecast widget.
struct ForecastList: View {
    let days: [Weather.Day]
    @Environment(\.timeZone) private var zone

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(days.dropFirst().prefix(6))) { day in
                HStack(spacing: 24) {
                    Text(day.date.formatted(Date.FormatStyle(timeZone: zone).weekday(.wide)))
                        .foregroundStyle(Theme.Palette.bone)
                        .frame(width: 220, alignment: .leading)
                    Image(systemName: Weather.describe(day.code, isDay: true).symbol)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(Theme.Palette.bone)
                        .frame(width: 60)
                    Text(day.precipitationChance >= 20 ? "\(day.precipitationChance)%" : " ")
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.cyan)
                    Spacer(minLength: 0)
                    Text(day.high, format: .temperature)
                        .foregroundStyle(Theme.Palette.bone)
                    Text(day.low, format: .temperature)
                        .foregroundStyle(Theme.Palette.faint)
                        .frame(width: 90, alignment: .trailing)
                }
                .font(Theme.Font.body)
                .frame(maxHeight: .infinity)
            }
        }
    }
}

struct TilePlaceholder: View {
    let text: String
    var body: some View {
        Text(text)
            .font(Theme.Font.body)
            .foregroundStyle(Theme.Palette.faint)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
