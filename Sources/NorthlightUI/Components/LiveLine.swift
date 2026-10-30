import SwiftUI
import NorthlightKit

/// A live event in one line: what is happening and how near it is.
public struct LiveLine: View {
    let event: LiveEvent
    let now: Date
    @Environment(\.timeZone) private var zone

    public init(_ event: LiveEvent, now: Date) {
        self.event = event
        self.now = now
    }

    public var body: some View {
        switch event {
        case .event(let event) where event.start > now:
            Text("\(event.title) in \(Int((event.start.timeIntervalSince(now) / 60).rounded(.up))) min")
        case .event(let event):
            Text("\(event.title), until \(event.end.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)))")
        case .aurora(let probability):
            Text("Aurora likely overhead, \(probability)%")
        case .quake(let quake, let distance):
            Text("M\(quake.magnitude, format: .number.precision(.fractionLength(1))), \(distance, format: .measurement(width: .abbreviated, usage: .road, numberFormatStyle: .number.precision(.fractionLength(0)))) away")
        case .squawk(let flight):
            Text("\(flight.label) squawking \(flight.squawk ?? ""), \(flight.emergency ?? "")")
        case .agent(let status) where status.activity == .waiting:
            Text("\(status.agent) is waiting for you")
        case .agent(let status):
            Text("\(status.agent): \(status.verb)")
        }
    }
}

/// The live dot. It pulses, or holds still under Reduce Motion.
public struct LiveDot: View {
    let color: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(color: Color) {
        self.color = color
    }

    public var body: some View {
        Circle()
            .fill(color)
            .frame(width: 16, height: 16)
            .phaseAnimator(reduceMotion ? [1.0] : [1.0, 0.3]) { dot, opacity in
                dot.opacity(opacity)
            } animation: { _ in
                .easeInOut(duration: 0.9)
            }
            .accessibilityHidden(true)
    }
}
