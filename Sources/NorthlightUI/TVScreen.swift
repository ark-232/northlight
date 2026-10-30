import SwiftUI
import NorthlightKit

/// The TV's screen: the sky, the header over the page, the drift and the night dim.
/// The TV draws it with its focus controls in `header` and `canvas`; the Mac draws
/// it as the mirror it edits.
public struct TVScreen<Header: View, Canvas: View>: View {
    let place: Place
    let mood: (Date) -> SkyMood
    let header: (Date) -> Header
    let canvas: (Date) -> Canvas
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(place: Place, mood: @escaping (Date) -> SkyMood, @ViewBuilder header: @escaping (Date) -> Header,
                @ViewBuilder canvas: @escaping (Date) -> Canvas) {
        self.place = place
        self.mood = mood
        self.header = header
        self.canvas = canvas
    }

    public var body: some View {
        ZStack {
            // The sky's colors follow the sun, cloud and aurora each minute; its drift
            // runs on its own 20 Hz timeline so it does not drag the 1 Hz data tree.
            TimelineView(.everyMinute) { context in
                SkyField(mood: mood(context.date))
            }

            TimelineView(.everyMinute) { context in
                let now = context.date
                // One container, because glass cannot sample other glass: surfaces in
                // separate containers sample inconsistently relative to each other.
                GlassEffectContainer(spacing: Theme.Metric.glassSpacing) {
                    VStack(spacing: Theme.Metric.tileSpacing) {
                        header(now)
                            .frame(height: 104)
                        canvas(now)
                    }
                }
                // The minute's step glides, so the drift never jumps; only the
                // offset takes the minute-long curve.
                .animation(reduceMotion ? nil : .linear(duration: 60)) { $0.offset(driftOffset(at: now)) }
                .overlay {
                    Rectangle()
                        .fill(.black)
                        .opacity(nightDim(at: now))
                        .allowsHitTesting(false)
                        .ignoresSafeArea()
                }
            }
        }
        .background(Theme.Palette.background.ignoresSafeArea())
    }

    /// Anti-retention wander. The periods are prime and mutually incommensurate,
    /// so the path does not retrace for weeks; 1620 and 2340 would share a factor
    /// of 180 and repeat every six hours. Peak velocity is about 0.04 pt/s,
    /// roughly 25× below the threshold at which a static edge is seen to move.
    private func driftOffset(at date: Date) -> CGSize {
        let t = date.timeIntervalSinceReferenceDate
        return CGSize(
            width: cos(2 * .pi * t / 1613) * 10,
            height: sin(2 * .pi * t / 2341) * 10
        )
    }

    /// Dims by up to 30 % as the sun sinks; Solar.nightDim holds the rule.
    private func nightDim(at date: Date) -> Double {
        0.30 * Solar.nightDim(at: date, latitude: place.latitude, longitude: place.longitude)
    }
}

/// The header is the one persistent glass surface: genuinely navigation-layer
/// chrome floating above content, which is where tvOS actually puts glass.
/// An active alert tints this bar rather than inserting its own row, so the layout
/// never jumps when an alert appears or clears.
public struct TVHeader<Center: View, Trailing: View>: View {
    let now: Date
    let browsing: Bool
    let dayLine: String?
    let alert: String?
    let center: Center
    let trailing: Trailing
    @Environment(\.timeZone) private var zone
    @Namespace private var glassNS

    /// `alert` is the first active alert's event, whose change animates.
    public init(now: Date, browsing: Bool, dayLine: String?, alert: String?,
                @ViewBuilder center: () -> Center, @ViewBuilder trailing: () -> Trailing) {
        self.now = now
        self.browsing = browsing
        self.dayLine = dayLine
        self.alert = alert
        self.center = center()
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 24) {
            clockBlock
                .frame(maxWidth: .infinity, alignment: .leading)
            center
            HStack(spacing: 24) { trailing }
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.horizontal, browsing ? 36 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // At rest the header sits on the sky; the glass bar comes back to hold the chips.
        .glassEffect(browsing ? .regular : .identity, in: .rect(cornerRadius: 28))
        .glassEffectID("header", in: glassNS)
        .background {
            // Keeps white text readable over a bright sky.
            LinearGradient(colors: [.black.opacity(browsing ? 0 : 0.35), .clear], startPoint: .top, endPoint: .bottom)
                .padding(.horizontal, -120).padding(.top, -80).padding(.bottom, -60)
                .allowsHitTesting(false)
        }
        .animation(Theme.Motion.page, value: browsing)
        .animation(Theme.Motion.data, value: alert)
    }

    /// The time and the day as one block: the second line sits on the clock's baseline
    /// and the first line's top meets the top of the numerals.
    private var clockBlock: some View {
        let time = now.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone))
        let parts = time.split(whereSeparator: \.isWhitespace)
        let suffix = parts.count > 1 && parts.last!.allSatisfy(\.isLetter) ? String(parts.last!) : nil
        let digits = suffix == nil ? time : parts.dropLast().joined(separator: " ")
        return HStack(alignment: .lastTextBaseline, spacing: 26) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text(digits).font(Theme.Font.time)
                if let suffix {
                    Text(suffix).font(Theme.Font.body).foregroundStyle(Theme.Palette.muted)
                }
            }
            .accessibilityElement(children: .combine)
            VStack(alignment: .leading, spacing: 12) {
                Text(now.formatted(Date.FormatStyle(timeZone: zone).weekday(.wide).month(.wide).day()))
                    .font(Theme.Font.title)
                    .foregroundStyle(Theme.Palette.bone)
                if !browsing, let dayLine {
                    Text(dayLine)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.muted)
                }
            }
            .lineLimit(1)
        }
    }
}

extension Snapshot {
    /// "37° · H 42° L 33° · Sunset 6:34 PM": the weather now and the next sun event.
    public var dayLine: String? {
        var parts: [String] = []
        if let weather = weather.value {
            parts.append(weather.temperature.formatted(.temperature))
            if let today = weather.days.first {
                parts.append("H \(today.high.formatted(.temperature)) L \(today.low.formatted(.temperature))")
            }
        }
        let time = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: place.timeZone)
        // Today's events, then tomorrow's sunrise once the sun has set.
        let days = [now, place.calendar.date(byAdding: .day, value: 1, to: now)!]
        let events = days.flatMap { day -> [(String, Date)] in
            guard case .risesAndSets(let sunrise, let sunset) = Solar.day(containing: day, latitude: place.latitude,
                                                                          longitude: place.longitude, calendar: place.calendar)
            else { return [] }
            return [("Sunrise", sunrise), ("Sunset", sunset)]
        }
        if let next = events.first(where: { $0.1 > now }) {
            parts.append("\(next.0) \(next.1.formatted(time))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// The first live widget on a page that is not on screen.
public struct LiveElsewhere {
    public let index: Int
    public let kind: WidgetConfig
    public let event: LiveEvent
}

extension Snapshot {
    public func liveElsewhere(in pages: [Page], shown: Page) -> LiveElsewhere? {
        for (index, other) in pages.enumerated() where other.id != shown.id {
            for placement in other.placements {
                if let event = live(for: placement.config) {
                    return LiveElsewhere(index: index, kind: placement.config, event: event)
                }
            }
        }
        return nil
    }
}

/// The live widget elsewhere in one line, with the page it is on.
public struct LiveElsewhereLabel: View {
    let elsewhere: LiveElsewhere
    let page: String
    let now: Date

    public init(_ elsewhere: LiveElsewhere, page: String, now: Date) {
        self.elsewhere = elsewhere
        self.page = page
        self.now = now
    }

    public var body: some View {
        HStack(spacing: 12) {
            LiveDot(color: Theme.Palette.cyan)
            LiveLine(elsewhere.event, now: now)
            Label(page, systemImage: "chevron.right")
                .foregroundStyle(.secondary)
        }
        .font(Theme.Font.body)
        .lineLimit(1)
    }
}

/// The header's right side at rest.
public struct TVHeaderStatus: View {
    let items: [HeaderStatus]
    let elsewhere: LiveElsewhere?
    let pages: [Page]
    let now: Date

    public init(items: [HeaderStatus], elsewhere: LiveElsewhere?, pages: [Page], now: Date) {
        self.items = items
        self.elsewhere = elsewhere
        self.pages = pages
        self.now = now
    }

    public var body: some View {
        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
            switch item {
            case .alert(let event, let more):
                HStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(more > 0 ? "\(event) +\(more)" : event)
                }
                .font(Theme.Font.body)
                .lineLimit(1)
                .padding(.horizontal, 22).padding(.vertical, 10)
                .glassEffect(.regular.tint(Theme.Palette.amber.opacity(0.35)), in: .capsule)
            case .liveElsewhere:
                if let elsewhere { LiveElsewhereLabel(elsewhere, page: pages[elsewhere.index].name, now: now) }
            case .agents(let count):
                Label("\(count)", systemImage: "terminal.fill")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Kind.tint(.agents))
                    .accessibilityLabel("\(count) agents running")
            case .usage(let percentage):
                HStack(spacing: 12) {
                    UsageRing(percentage: percentage, diameter: 40, lineWidth: 6)
                    Text("\(Int(percentage.rounded()))%")
                        .font(Theme.Font.body)
                        .monospacedDigit()
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Claude 5-hour usage \(Int(percentage.rounded())) percent")
            case .networkFault:
                Image(systemName: "wifi.exclamationmark")
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.amber)
                    .accessibilityLabel("No network")
            case .stale(let age):
                Text("\(age.shortAge) old")
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.Palette.amber)
            }
        }
    }
}
