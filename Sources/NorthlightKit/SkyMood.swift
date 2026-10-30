import Foundation

/// What the sky behind the dashboard shows: the light of the sun's height, dulled
/// by cloud, with an aurora's green across the top when one is likely in a dark sky.
public struct SkyMood: Equatable, Sendable {
    public struct RGB: Equatable, Sendable {
        public var red, green, blue: Double

        init(_ red: Double, _ green: Double, _ blue: Double) {
            self.red = red; self.green = green; self.blue = blue
        }
    }

    /// The 3 × 3 mesh, row by row from the top: overhead down to the horizon.
    public let colors: [RGB]
    /// How far the mesh wanders, 1 being its usual drift.
    public let drift: Double

    public init(sunElevation: Double, cloudCover: Int?, auroraProbability: Int?) {
        let (zenith, horizon) = Self.light(at: sunElevation)
        let cloud = Double(cloudCover ?? 0) / 100
        // An aurora shows once the sky is past nautical twilight, fully from -18 degrees.
        let dark = min(1, max(0, (-12 - sunElevation) / 6))
        let aurora = min(1, max(0, Double((auroraProbability ?? 0) - 20) / 60)) * dark * (1 - cloud)

        let rows = [
            zenith.mixed(with: Self.auroraGreen, by: 0.6 * aurora),
            zenith.mixed(with: horizon, by: 0.5).mixed(with: Self.auroraGlow, by: 0.3 * aurora),
            horizon,
        ].map { $0.dulled(by: 0.7 * cloud) }
        // Each row's corners sit a little deeper than its middle.
        colors = rows.flatMap { [$0.scaled(by: 0.9), $0, $0.scaled(by: 0.9)] }
        drift = 1 + 0.6 * aurora
    }

    /// The mesh's points at `t` seconds, row by row like `colors`, in unit
    /// coordinates. Corners stay pinned and the edge midpoints slide along their
    /// edges, so the mesh always covers the screen; the center wanders freely. At a
    /// drift of 1 the peak velocity works out to about 4.8 pt/s (0.078°/s at ten
    /// feet), inside the ambient band where motion registers as "alive" rather than
    /// "something moved".
    public func points(at t: Double) -> [SIMD2<Float>] {
        func wander(_ index: Int) -> SIMD2<Float> {
            let period = Self.periods[index]
            let phase = Double(index) * .pi / 2
            return SIMD2(Float(0.06 * drift * sin(2 * .pi * t / period + phase)),
                         Float(0.06 * drift * cos(2 * .pi * t / (period * 1.21) + phase)))
        }
        let top = wander(0), left = wander(1), right = wander(2), bottom = wander(3), center = wander(4)

        return [
            SIMD2(0, 0),            SIMD2(0.5 + top.x, 0),    SIMD2(1, 0),
            SIMD2(0, 0.5 + left.y), SIMD2(0.5, 0.5) + center, SIMD2(1, 0.5 + right.y),
            SIMD2(0, 1),            SIMD2(0.5 + bottom.x, 1), SIMD2(1, 1),
        ]
    }

    /// Drift periods are mutually incommensurate primes, so the field never
    /// visibly retraces. Values near a common factor repeat within hours.
    private static let periods: [Double] = [137, 151, 173, 191, 211]

    private static let auroraGreen = RGB(0.102, 0.361, 0.251)   // #1A5C40
    private static let auroraGlow = RGB(0.078, 0.235, 0.188)    // #143C30

    /// Overhead and horizon colors by the sun's height. Night is the quiet palette,
    /// what shows for most of the year; day stays dark enough for the tiles.
    private static let stops: [(elevation: Double, zenith: RGB, horizon: RGB)] = [
        (-18, RGB(0.039, 0.063, 0.094), RGB(0.047, 0.078, 0.125)),   // night
        (-12, RGB(0.043, 0.071, 0.133), RGB(0.078, 0.118, 0.220)),   // nautical dusk
        (-6, RGB(0.055, 0.090, 0.188), RGB(0.165, 0.149, 0.314)),    // blue hour
        (0, RGB(0.078, 0.125, 0.220), RGB(0.290, 0.180, 0.243)),     // sunset
        (6, RGB(0.102, 0.157, 0.251), RGB(0.353, 0.227, 0.141)),     // golden hour
        (15, RGB(0.094, 0.157, 0.235), RGB(0.133, 0.204, 0.290)),    // day
    ]

    private static func light(at elevation: Double) -> (zenith: RGB, horizon: RGB) {
        guard let upper = stops.firstIndex(where: { $0.elevation >= elevation }) else {
            return (stops[stops.count - 1].zenith, stops[stops.count - 1].horizon)
        }
        guard upper > 0 else { return (stops[0].zenith, stops[0].horizon) }
        let below = stops[upper - 1], above = stops[upper]
        let t = (elevation - below.elevation) / (above.elevation - below.elevation)
        return (below.zenith.mixed(with: above.zenith, by: t), below.horizon.mixed(with: above.horizon, by: t))
    }
}

private extension SkyMood.RGB {
    func mixed(with other: Self, by t: Double) -> Self {
        Self(red + (other.red - red) * t, green + (other.green - green) * t, blue + (other.blue - blue) * t)
    }

    /// Toward its own gray, so cloud takes the color out without darkening it.
    func dulled(by t: Double) -> Self {
        let gray = (red + green + blue) / 3
        return mixed(with: Self(gray, gray, gray), by: t)
    }

    func scaled(by factor: Double) -> Self {
        Self(red * factor, green * factor, blue * factor)
    }
}
