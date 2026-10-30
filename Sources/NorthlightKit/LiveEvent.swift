import Foundation

/// Something happening now that a widget shows in place: a live dot, a glow, and the
/// event as its first line (D13).
public enum LiveEvent: Equatable, Sendable {
    case event(CalendarEvent)
    case aurora(probability: Int)
    case quake(Quake, distance: Measurement<UnitLength>)
    case squawk(Flight)
    case agent(AgentStatus)

    /// A timed event from ten minutes before its start to its end. The latest to start
    /// wins, so the next meeting shows over one under way.
    public static func agenda(_ events: [CalendarEvent], at now: Date) -> LiveEvent? {
        events.filter { !$0.isAllDay && $0.start.addingTimeInterval(-600) <= now && now < $0.end }
            .max { $0.start < $1.start }
            .map(LiveEvent.event)
    }

    /// OVATION's chance at the place of 30 % or more, with the sun below −12° and less
    /// than half the sky clouded.
    public static func aurora(_ aurora: Aurora, sunElevation: Double, cloudCover: Int?) -> LiveEvent? {
        guard let probability = aurora.localProbability, probability >= 30, sunElevation < -12,
              let cloudCover, cloudCover < 50
        else { return nil }
        return .aurora(probability: probability)
    }

    /// The largest quake of M4.0 or more within 300 km in the last hour.
    public static func quakes(_ quakes: [Quake], around place: Place, at now: Date) -> LiveEvent? {
        let near = quakes.compactMap { quake -> (Quake, Measurement<UnitLength>)? in
            guard quake.magnitude >= 4, now.timeIntervalSince(quake.time) <= 3_600,
                  let latitude = quake.latitude, let longitude = quake.longitude
            else { return nil }
            // Haversine, on a sphere of the Earth's mean radius.
            let φ1 = place.latitude * .pi / 180, φ2 = latitude * .pi / 180
            let Δφ = φ2 - φ1, Δλ = (longitude - place.longitude) * .pi / 180
            let a = sin(Δφ / 2) * sin(Δφ / 2) + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
            let distance = Measurement(value: 2 * 6_371.0088 * asin(min(1, a.squareRoot())), unit: UnitLength.kilometers)
            return distance <= Measurement(value: 300, unit: .kilometers) ? (quake, distance) : nil
        }
        return near.max { $0.0.magnitude < $1.0.magnitude }.map { .quake($0.0, distance: $0.1) }
    }

    /// The nearest aircraft squawking an emergency.
    public static func flights(_ flights: [Flight]) -> LiveEvent? {
        flights.filter { $0.emergency != nil }
            .min { ($0.distanceNM ?? .infinity) < ($1.distanceNM ?? .infinity) }
            .map(LiveEvent.squawk)
    }

    /// A running turn, and first one waiting on the user.
    public static func agents(_ statuses: [AgentStatus]) -> LiveEvent? {
        let running = statuses.filter { $0.activity != .idle }
        return (running.first { $0.activity == .waiting } ?? running.first).map(LiveEvent.agent)
    }
}
