import SwiftUI
import NorthlightKit

/// The sky behind everything.
///
/// This layer is what makes the rest of the design possible: `Material` and
/// Liquid Glass both sample what is behind them, so on pure black they collapse
/// into flat gray rectangles. Giving them something to refract is the single
/// change that stops the dashboard reading as a web page.
///
/// It lives in its own `TimelineView` so a 20 Hz drift does not drag the 1 Hz
/// data tree along with it.
public struct SkyField: View {
    let mood: SkyMood

    /// A clear night unless the mood says otherwise.
    public init(mood: SkyMood = SkyMood(sunElevation: -90, cloudCover: nil, auroraProbability: nil)) {
        self.mood = mood
    }

    private static let breathPeriod: Double = 90

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        ZStack {
            // L0 — never pure black: #000000 reveals backlight non-uniformity
            // and makes local-dimming pumping visible on an LED panel.
            Color(white: 0.04)

            TimelineView(.animation(minimumInterval: 1.0 / 20.0, paused: scenePhase != .active || reduceMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                MeshGradient(
                    width: 3,
                    height: 3,
                    points: mood.points(at: t),
                    colors: mood.colors.map { Color(red: $0.red, green: $0.green, blue: $0.blue) },
                    smoothsColors: true,
                    colorSpace: .perceptual
                )
                // A slow global breath keeps a still frame from reading as dead.
                .brightness(0.04 * sin(2 * .pi * t / Self.breathPeriod))
            }

            // L6 — four eased stops, not two. A two-stop ramp produces a visible
            // Mach band across the middle of the screen.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.00), location: 0.00),
                    .init(color: .black.opacity(0.10), location: 0.35),
                    .init(color: .black.opacity(0.22), location: 0.72),
                    .init(color: .black.opacity(0.30), location: 1.00),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
