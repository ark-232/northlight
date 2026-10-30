import MapKit
import NorthlightKit
import SwiftUI

/// The space station on a map that follows it, with the ground track it has flown while the
/// widget watched, and its altitude and speed.
struct ISSTile: View {
    let feed: Loaded<ISSTrack>
    let now: Date
    @Environment(\.widgetSize) private var size
    @Environment(\.widgetKind) private var kind

    private var tint: Color { kind.map(Theme.Kind.tint) ?? Theme.Palette.bone }

    var body: some View {
        Tile(label: "ISS", trailing: feed.trailing(asOf: now)) {
            FeedBody(state: feed.state(asOf: now)) { track in
                if let fix = track.latest {
                    let layout = size == .large ? AnyLayout(VStackLayout(alignment: .leading, spacing: 20))
                                                : AnyLayout(HStackLayout(alignment: .top, spacing: 24))
                    layout {
                        map(track, at: fix)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        numbers(fix)
                    }
                } else {
                    TilePlaceholder(text: "Finding the station")
                }
            }
        }
    }

    /// Follows the station, wide enough to show the last half hour of its track;
    /// MapKit will not fit the whole world into a widget.
    private func map(_ track: ISSTrack, at fix: ISSFix) -> some View {
        let around = MKCoordinateRegion(center: fix.coordinate, span: MKCoordinateSpan(latitudeDelta: 80, longitudeDelta: 160))
        return Map(position: .constant(.region(around)), interactionModes: []) {
            ForEach(Array(track.segments.enumerated()), id: \.offset) { _, run in
                MapPolyline(coordinates: run.map(\.coordinate))
                    .stroke(tint.opacity(0.7), lineWidth: 4)
            }
            Annotation("", coordinate: fix.coordinate) {
                Circle()
                    .fill(tint)
                    .stroke(Theme.Palette.bone, lineWidth: 3)
                    .frame(width: 22, height: 22)
                    .shadow(color: tint, radius: 12)
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func numbers(_ fix: ISSFix) -> some View {
        let large = size == .large
        let distance = Measurement(value: fix.altitudeKM, unit: UnitLength.kilometers)
        let speed = Measurement(value: fix.velocityKMH, unit: UnitSpeed.kilometersPerHour)
        let whole = FloatingPointFormatStyle<Double>.number.precision(.fractionLength(0))
        let lines = large ? AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 36))
                          : AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
        return lines {
            Text(distance, format: .measurement(width: .abbreviated, usage: .road, numberFormatStyle: whole))
                .font(large ? Theme.Font.tileValue : Theme.Font.title)
                .foregroundStyle(Theme.Palette.bone)
                .numericChange(fix.altitudeKM.rounded())
            Text(speed, format: .measurement(width: .abbreviated, usage: .general, numberFormatStyle: whole))
                .font(Theme.Font.body)
                .foregroundStyle(Theme.Palette.bone)
                .numericChange(fix.velocityKMH.rounded())
            Text(fix.sunlit ? "In sunlight" : "In the Earth's shadow")
                .font(Theme.Font.caption)
                .foregroundStyle(fix.sunlit ? Theme.Palette.amber : Theme.Palette.muted)
            Text(Self.position(fix))
                .font(Theme.Font.caption)
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.faint)
        }
        .lineLimit(1)
        .fixedSize(horizontal: !large, vertical: false)
    }

    private static func position(_ fix: ISSFix) -> String {
        String(format: "%.1f° %@ %.1f° %@", abs(fix.latitude), fix.latitude < 0 ? "S" : "N",
               abs(fix.longitude), fix.longitude < 0 ? "W" : "E")
    }
}

private extension ISSFix {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
