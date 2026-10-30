import Charts
import NorthlightKit
import SwiftUI

/// The solar wind arriving at L1, the Sun's X-ray output and NOAA's scales. At
/// large size, six hours of X-ray flux on the flare-class ladder.
struct SpaceWeatherTile: View {
    let feed: Loaded<SpaceWeather>
    /// Fetched only while a large widget is placed.
    let xrays: Loaded<[SpaceWeather.XRay]>
    let now: Date
    @Environment(\.widgetSize) private var size
    @Environment(\.calendar) private var calendar

    var body: some View {
        Tile(label: "Space weather", trailing: feed.trailing(asOf: now)) {
            FeedBody(state: feed.state(asOf: now)) { weather in
                VStack(alignment: .leading, spacing: 18) {
                    if size == .small {
                        speed(weather.wind)
                        bz(weather.wind)
                        flareNow(weather)
                    } else {
                        HStack(alignment: .top, spacing: 24) {
                            speed(weather.wind)
                            Spacer(minLength: 0)
                            VStack(alignment: .trailing, spacing: 10) {
                                bz(weather.wind)
                                flareNow(weather)
                                if let flare = weather.flare {
                                    Text("Last flare \(flare.peakClass) at \(flare.peak, format: Date.FormatStyle(date: .omitted, time: .shortened, timeZone: calendar.timeZone))")
                                        .font(Theme.Font.caption)
                                        .foregroundStyle(Theme.Palette.muted)
                                        .lineLimit(1)
                                }
                            }
                        }
                        ScaleChips(scales: weather.scales)
                        if size == .large, case .ready(let history) = xrays.state(asOf: now), history.count > 1 {
                            XRayChart(xrays: history)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private func speed(_ wind: SpaceWeather.Wind) -> some View {
        if let speed = wind.speed {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("\(Int(speed.rounded()))")
                    .font(size == .small ? Theme.Font.tileValue : Theme.Font.hero)
                    .foregroundStyle(speed >= 600 ? Theme.Palette.amber : Theme.Palette.bone)
                    .numericChange(speed)
                Text("km/s")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.muted)
            }
            .lineLimit(1)
        } else {
            TilePlaceholder(text: "No solar wind reading")
        }
    }

    /// Southward Bz couples the solar wind into the magnetosphere; a few nT south is
    /// worth noticing, ten or more drives storms.
    @ViewBuilder private func bz(_ wind: SpaceWeather.Wind) -> some View {
        if let bz = wind.bz {
            let color = bz <= -10 ? Theme.Palette.red : bz < -3 ? Theme.Palette.amber : bz < 0 ? Theme.Palette.bone : Theme.Palette.green
            Text("Bz \(bz, specifier: "%+.0f") nT \(bz < 0 ? "south" : "north")")
                .font(Theme.Font.body)
                .foregroundStyle(color)
                .numericChange(bz)
                .lineLimit(1)
        }
    }

    @ViewBuilder private func flareNow(_ weather: SpaceWeather) -> some View {
        if let current = weather.currentClass {
            Text("X-ray \(current)")
                .font(Theme.Font.body)
                .foregroundStyle(flareColor(current))
                .lineLimit(1)
        }
    }

    private func flareColor(_ flareClass: String) -> Color {
        switch flareClass.first {
        case "X": Theme.Palette.red
        case "M": Theme.Palette.amber
        default: Theme.Palette.bone
        }
    }
}

/// NOAA's radio blackout, radiation storm and geomagnetic storm levels today.
private struct ScaleChips: View {
    let scales: SpaceWeather.Scales

    var body: some View {
        HStack(spacing: 16) {
            chip("R", scales.r, name: "Radio blackout")
            chip("S", scales.s, name: "Radiation storm")
            chip("G", scales.g, name: "Geomagnetic storm")
        }
    }

    private func chip(_ letter: String, _ level: Int, name: String) -> some View {
        Text("\(letter)\(level)")
            .font(Theme.Font.label)
            .monospacedDigit()
            .foregroundStyle(level == 0 ? Theme.Palette.muted : Theme.Palette.background)
            .padding(.horizontal, 18)
            .padding(.vertical, 6)
            .background(Capsule().fill(level == 0 ? Theme.Palette.surface : level < 3 ? Theme.Palette.amber : Theme.Palette.red))
            .accessibilityLabel("\(name) level \(level)")
    }
}

/// The 0.1 to 0.8 nm flux on a log axis fixed from A to X, so the line moves and
/// the scale never does.
private struct XRayChart: View {
    let xrays: [SpaceWeather.XRay]
    @Environment(\.widgetKind) private var kind

    var body: some View {
        Chart(xrays, id: \.time) { point in
            LineMark(x: .value("Time", point.time), y: .value("Flux", point.flux))
                .foregroundStyle(kind.map(Theme.Kind.tint) ?? Theme.Palette.bone)
                .lineStyle(StrokeStyle(lineWidth: 3))
        }
        .chartYScale(domain: 1e-8...1e-3, type: .log)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .leading, values: [1e-6, 1e-5, 1e-4]) { value in
                AxisGridLine().foregroundStyle(Theme.Palette.hairline)
                AxisValueLabel {
                    if let flux = value.as(Double.self) {
                        Text(flux >= 1e-4 ? "X" : flux >= 1e-5 ? "M" : "C")
                            .font(Theme.Font.caption)
                            .foregroundStyle(Theme.Palette.faint)
                    }
                }
            }
        }
        .accessibilityLabel("X-ray flux over six hours")
    }
}
