import SwiftUI
import NorthlightKit

/// Dark-only palette and a type scale sized for a couch.
///
/// Two deliberate removals from the first pass: the 1 pt hairline borders on
/// tiles and the rounded font. Together they were most of what read as
/// third-party — tvOS separates surfaces with material and elevation, not with
/// strokes, and uses San Francisco, not SF Rounded. Under Increase Contrast the
/// grays brighten and tiles take a border.
public enum Theme {
    public enum Palette {
        /// Fallback only. The sky field owns the background now, and it is
        /// never pure black: #000000 reveals backlight non-uniformity and makes
        /// local-dimming pumping visible on an LED panel.
        public static let background = Color(white: 0.04)

        /// Retained for small inner surfaces (forecast cells), which sit on a
        /// tile rather than on the sky and so cannot use a material.
        public static let surface = contrast(.white.opacity(0.06), .white.opacity(0.16))
        public static let hairline = contrast(.white.opacity(0.10), .white.opacity(0.35))

        public static let bone = Color(white: 0.90)
        public static let muted = contrast(Color(white: 0.58), Color(white: 0.80))
        public static let faint = contrast(Color(white: 0.40), Color(white: 0.66))

        public static let cyan = Color(red: 0.13, green: 0.83, blue: 0.93)
        public static let green = Color(red: 0.29, green: 0.87, blue: 0.50)
        public static let amber = Color(red: 0.96, green: 0.62, blue: 0.04)
        public static let red = Color(red: 0.94, green: 0.27, blue: 0.27)
        public static let violet = Color(red: 0.65, green: 0.55, blue: 0.98)

        private static func contrast(_ normal: Color, _ increased: Color) -> Color {
            #if canImport(UIKit)
            let normal = UIColor(normal), increased = UIColor(increased)
            return Color(UIColor { $0.accessibilityContrast == .high ? increased : normal })
            #else
            let normal = NSColor(normal), increased = NSColor(increased)
            return Color(NSColor(name: nil) { appearance in
                let match = appearance.bestMatch(from: [.darkAqua, .accessibilityHighContrastDarkAqua])
                return match == .accessibilityHighContrastDarkAqua ? increased : normal
            })
            #endif
        }
    }

    /// Three hard bands, mapped to viewing distance at ten feet. The first pass
    /// had eight sizes clustered between 22 and 30 pt, which is exactly why
    /// nothing drew the eye: with everything emphasised, nothing is.
    ///
    /// Band 1 (≥41 pt) reads across the room, band 2 (27–41 pt) on approach,
    /// band 3 (25 pt) only if you stop and look. Nothing below 23 pt exists
    /// here, because it is unreadable at this distance.
    ///
    /// Every live number is `.monospacedDigit()` so its trailing edge does not
    /// shift as digits change.
    public enum Font {
        // Band 1 — across the room
        public static let hero = SwiftUI.Font.system(size: 116, weight: .bold).monospacedDigit()
        public static let heroLarge = SwiftUI.Font.system(size: 172, weight: .bold).monospacedDigit()
        public static let clock = SwiftUI.Font.system(size: 72, weight: .semibold).monospacedDigit()
        /// The header's time.
        public static let time = SwiftUI.Font.system(size: 88, weight: .semibold).monospacedDigit()
        public static let promoted = SwiftUI.Font.system(size: 96, weight: .semibold).monospacedDigit()
        /// A number that changes as you watch, such as a speed test's.
        public static let live = SwiftUI.Font.system(size: 64, weight: .semibold).monospacedDigit()

        // Band 2 — on approach
        public static let tileValue = SwiftUI.Font.system(size: 57, weight: .semibold).monospacedDigit()
        public static let title = SwiftUI.Font.system(size: 38, weight: .medium)
        public static let body = SwiftUI.Font.system(size: 31, weight: .medium)
        public static let bodySmall = SwiftUI.Font.system(size: 31, weight: .medium)

        // Band 3 — detail
        public static let caption = SwiftUI.Font.system(size: 25, weight: .medium)
        public static let label = SwiftUI.Font.system(size: 25, weight: .semibold)
    }

    public enum Metric {
        /// Zero: tvOS already supplies a 60/80 pt title-safe inset. Adding more
        /// on top of it threw away 80 pt in each axis.
        public static let screenPadding: CGFloat = 0
        public static let tileSpacing: CGFloat = 40
        public static let tilePadding: CGFloat = 30
        public static let corner: CGFloat = 36
        /// Must stay below the layout gutter, or adjacent glass surfaces fuse
        /// into one blob at rest.
        public static let glassSpacing: CGFloat = 24
    }

    /// Each widget kind's mark: one symbol and one tint, used for its label, its wash
    /// and its main chart mark. Status colours (green, amber, red) stay separate.
    public enum Kind {
        public static func symbol(_ kind: WidgetConfig) -> String {
            switch kind {
            case .weather: "cloud.sun.fill"
            case .forecast: "calendar"
            case .agenda: "calendar.badge.clock"
            case .aurora: "sparkles"
            case .daylight: "sun.horizon.fill"
            case .airSnow: "snowflake"
            case .seismic: "waveform.path.ecg"
            case .flights: "airplane"
            case .github: "chevron.left.forwardslash.chevron.right"
            case .githubLines: "chart.xyaxis.line"
            case .githubCommits: "chart.bar.fill"
            case .githubInbox: "tray.full.fill"
            case .githubActions: "play.circle.fill"
            case .agents: "terminal.fill"
            case .network: "wifi"
            case .briefing: "text.quote"
            case .spaceWeather: "sun.max.fill"
            case .iss: "globe.americas.fill"
            case .launches: "flame.fill"
            case .hackerNews: "newspaper.fill"
            case .serviceStatus: "server.rack"
            case .kev: "exclamationmark.shield.fill"
            case .markets: "chart.line.uptrend.xyaxis"
            }
        }

        public static func tint(_ kind: WidgetConfig) -> Color {
            switch kind {
            case .weather, .forecast: Color(red: 0.35, green: 0.78, blue: 0.98)
            case .agenda: Palette.violet
            case .aurora: Color(red: 0.36, green: 0.90, blue: 0.72)
            case .daylight: Palette.amber
            case .airSnow: Color(red: 0.65, green: 0.89, blue: 1.0)
            case .seismic: Color(red: 1.0, green: 0.48, blue: 0.35)
            case .flights: Color(red: 0.49, green: 0.48, blue: 1.0)
            case .github, .githubLines, .githubCommits: Color(red: 0.25, green: 0.73, blue: 0.31)
            // GitHub's merged-pull-request purple.
            case .githubInbox: Color(red: 0.64, green: 0.44, blue: 0.97)
            // The Actions mark's blue.
            case .githubActions: Color(red: 0.33, green: 0.62, blue: 1.0)
            case .agents: Color(red: 1.0, green: 0.62, blue: 0.04)
            case .network: Color(red: 0.19, green: 0.84, blue: 0.78)
            case .briefing: Palette.bone
            case .spaceWeather: Color(red: 0.91, green: 0.42, blue: 1.0)
            case .iss: Color(red: 0.30, green: 0.55, blue: 1.0)
            case .launches: Color(red: 0.71, green: 0.90, blue: 0.33)
            case .hackerNews: Color(red: 1.0, green: 0.84, blue: 0.04)
            case .serviceStatus: Color(red: 0.72, green: 0.74, blue: 0.88)
            case .kev: Color(red: 1.0, green: 0.44, blue: 0.71)
            case .markets: Color(red: 0.86, green: 0.76, blue: 0.55)
            }
        }
    }

    /// Every curve the app uses; nothing else names one.
    public enum Motion {
        /// Page turns, the detail zoom, dots becoming chips.
        public static let page = Animation.spring(duration: 0.5, bounce: 0)
        /// Numbers, charts and live state settling on new data.
        public static let data = Animation.smooth(duration: 0.6)
        /// Focus lifting a tile, a carried tile, chips.
        public static let lift = Animation.snappy(duration: 0.3)
        /// A new row arriving: a commit, a quake, a tool chip.
        public static let insert = Animation.spring(duration: 0.4, bounce: 0.15)
    }
}

/// Standard tile chrome: a platter the sky shows through, washed with the kind's
/// tint from the top-leading corner, and a label row of the kind's symbol and name.
struct Tile<Content: View>: View {
    let label: String
    var accent: Color = Theme.Palette.muted
    var trailing: String? = nil
    @ViewBuilder var content: Content
    @Environment(\.colorSchemeContrast) private var contrast
    @Environment(\.isLive) private var isLive
    @Environment(\.widgetKind) private var kind

    private var tint: Color { kind.map(Theme.Kind.tint) ?? accent }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .firstTextBaseline) {
                HStack(spacing: 12) {
                    if isLive {
                        LiveDot(color: tint)
                    } else if let kind {
                        Image(systemName: Theme.Kind.symbol(kind))
                            .foregroundStyle(tint)
                            .accessibilityHidden(true)
                    }
                    Text(label)
                        .foregroundStyle(Theme.Palette.muted)
                }
                .font(Theme.Font.label)
                Spacer(minLength: 12)
                if let trailing {
                    Text(trailing)
                        .font(Theme.Font.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Palette.amber)
                }
            }
            content
            Spacer(minLength: 0)
        }
        .padding(Theme.Metric.tilePadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        // Content that outgrows its cell is cut at the tile's edge, never drawn over a neighbour.
        .clipShape(RoundedRectangle(cornerRadius: Theme.Metric.corner, style: .continuous))
        .background {
            let shape = RoundedRectangle(cornerRadius: Theme.Metric.corner, style: .continuous)
            ZStack {
                shape.fill(.regularMaterial)
                shape.fill(.white.opacity(0.08))
                shape.fill(LinearGradient(colors: [tint.opacity(0.12), .clear], startPoint: .topLeading, endPoint: .center))
            }
            .shadow(color: tint.opacity(isLive ? 0.6 : 0), radius: 36)
        }
        .overlay {
            if isLive {
                RoundedRectangle(cornerRadius: Theme.Metric.corner, style: .continuous)
                    .strokeBorder(tint, lineWidth: 3)
            } else if contrast == .increased {
                RoundedRectangle(cornerRadius: Theme.Metric.corner, style: .continuous)
                    .strokeBorder(Theme.Palette.hairline, lineWidth: 3)
            }
        }
        .containerShape(RoundedRectangle(cornerRadius: Theme.Metric.corner, style: .continuous))
        // One VoiceOver element per widget, read from what it shows.
        .accessibilityElement(children: .combine)
    }
}

/// A button that draws nothing of its own, for focus targets that stay invisible.
extension View {
    /// Rolls a changing number into place, or crossfades it under Reduce Motion.
    func numericChange<V: Equatable>(_ value: V) -> some View {
        modifier(NumericChange(value: value))
    }
}

private struct NumericChange<V: Equatable>: ViewModifier {
    let value: V
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .contentTransition(reduceMotion ? .opacity : .numericText())
            .animation(Theme.Motion.data, value: value)
    }
}

public struct InvisibleButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// A tile's body for one feed: its content only while the feed is ready, so a
/// failed feed says so instead of falling through to the empty sentence.
struct FeedBody<T: Codable & Sendable, Content: View>: View {
    let state: Loaded<T>.State
    @ViewBuilder let content: (T) -> Content

    var body: some View {
        switch state {
        case .loading:
            TilePlaceholder(text: "Loading")
        case .ready(let value):
            content(value)
        case .unavailable(let reason):
            VStack(alignment: .leading, spacing: 8) {
                TilePlaceholder(text: "Unavailable, retrying")
                Text(reason)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.faint)
                    .lineLimit(2)
            }
        }
    }
}

extension Loaded {
    /// The tile header's note: the age once the value is stale, and a failing refresh.
    func trailing(asOf now: Date) -> String? {
        switch (staleAge(asOf: now), lastError) {
        case (let age?, nil): "\(age.shortAge) old"
        case (let age?, _?): "\(age.shortAge) old · retrying"
        case (nil, _?): "Retrying"
        case (nil, nil): nil
        }
    }
}
