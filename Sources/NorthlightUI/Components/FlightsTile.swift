import MapKit
import NorthlightKit
import SwiftUI

/// Aircraft around the place on a map, each with the path it has flown lately.
/// Coverage comes from volunteer ADS-B receivers, so an empty map means "nothing
/// heard", not "nothing flying".
struct FlightsTile: View {
    let feed: Loaded<[Flight]>
    let trails: FlightTrails
    let place: Place
    let radiusNM: Int
    let now: Date

    var body: some View {
        Tile(label: "Overhead", accent: Theme.Palette.violet, trailing: feed.trailing(asOf: now)) {
            FeedBody(state: feed.state(asOf: now)) { flights in
                ZStack(alignment: .bottomLeading) {
                    map(flights)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    if flights.isEmpty {
                        TilePlaceholder(text: "Nothing heard within \(radiusNM) nm")
                            .padding(20)
                    }
                }
            }
        }
    }

    private func map(_ flights: [Flight]) -> some View {
        let home = CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
        let across = Double(radiusNM) * 1_852 * 2
        return Map(initialPosition: .region(MKCoordinateRegion(center: home, latitudinalMeters: across, longitudinalMeters: across)),
                   interactionModes: []) {
            // First, so aircraft and their labels draw over it.
            Annotation("", coordinate: home) {
                Circle()
                    .fill(Theme.Palette.bone)
                    .frame(width: 12, height: 12)
            }
            ForEach(flights) { flight in
                if let path = trails.paths[flight.id], let here = position(of: flight, along: path) {
                    MapPolyline(coordinates: (path + [here]).map(\.coordinate))
                        .stroke(Theme.Palette.violet.opacity(0.55), lineWidth: 3)
                    Annotation("", coordinate: here.coordinate) {
                        marker(for: flight)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .environment(\.colorScheme, .dark)
        .allowsHitTesting(false)
    }

    /// The last fix, flown on along the aircraft's track for up to 30 seconds, so it
    /// moves between polls instead of jumping.
    private func position(of flight: Flight, along path: [FlightTrails.Point]) -> FlightTrails.Point? {
        guard let fix = path.last else { return nil }
        guard !flight.onGround, let knots = flight.groundSpeedKnots, let track = flight.track else { return fix }
        return fix.flown(knots: knots, track: track, to: min(now, fix.time.addingTimeInterval(30)))
    }

    @ViewBuilder
    private func marker(for flight: Flight) -> some View {
        if flight.onGround {
            Circle()
                .fill(Theme.Palette.faint)
                .frame(width: 8, height: 8)
        } else {
            // An aircraft squawking an emergency shows its code, in red.
            let emergency = flight.emergency != nil
            VStack(spacing: 4) {
                // The symbol points east, so a track of 90 degrees leaves it as drawn.
                Image(systemName: "airplane")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(emergency ? Theme.Palette.red : Theme.Palette.bone)
                    .rotationEffect(.degrees((flight.track ?? 90) - 90))
                Text(emergency ? "\(flight.label) \(flight.squawk ?? "")" : "\(flight.label) \(altitudeText(flight))")
                    .font(.system(size: 17, weight: emergency ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(emergency ? Theme.Palette.red : Theme.Palette.muted)
                    .fixedSize()
            }
        }
    }

    private func altitudeText(_ flight: Flight) -> String {
        guard let feet = flight.altitudeFeet else { return "" }
        // Flight levels above the transition altitude read the way ATC says them.
        if feet >= 18_000 { return "FL\(feet / 100)" }
        // Below 1,000 ft, integer-dividing by 1,000 renders everything as "0k".
        if feet < 1_000 { return "\(feet) ft" }
        return String(format: "%.1fk ft", Double(feet) / 1_000)
    }
}

private extension FlightTrails.Point {
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
