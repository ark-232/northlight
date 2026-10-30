import Foundation

/// Where each aircraft has been lately, built up poll by poll for the map.
public struct FlightTrails: Equatable, Sendable {
    public struct Point: Equatable, Sendable {
        public var latitude: Double
        public var longitude: Double
        public var time: Date

        /// Where the aircraft is at `date` if it has held its track and speed since this fix.
        public func flown(knots: Double, track: Double, to date: Date) -> Point {
            let nauticalMiles = knots * date.timeIntervalSince(time) / 3_600
            let heading = track * .pi / 180
            let north = nauticalMiles * cos(heading) / 60
            let east = nauticalMiles * sin(heading) / (60 * cos(latitude * .pi / 180))
            return Point(latitude: latitude + north, longitude: longitude + east, time: date)
        }
    }

    /// How far back a path reaches.
    public static let span: TimeInterval = 10 * 60
    /// How long an aircraft can go unheard before it leaves the map.
    public static let silence: TimeInterval = 2 * 60

    public private(set) var paths: [String: [Point]] = [:]

    public init() {}

    public mutating func record(_ flights: [Flight], at now: Date) {
        for flight in flights {
            guard let latitude = flight.latitude, let longitude = flight.longitude else { continue }
            paths[flight.id, default: []].append(Point(latitude: latitude, longitude: longitude, time: now))
        }
        paths = paths.compactMapValues { path in
            guard let last = path.last, now.timeIntervalSince(last.time) <= Self.silence else { return nil }
            return path.filter { now.timeIntervalSince($0.time) <= Self.span }
        }
    }
}
