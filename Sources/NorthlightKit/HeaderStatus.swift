import Foundation

/// What the header's right side shows: at most three items, most urgent first.
public enum HeaderStatus: Equatable, Sendable {
    case alert(String, more: Int)
    case liveElsewhere
    case agents(Int)
    /// The Claude account's 5-hour usage, in percent.
    case usage(Double)
    case networkFault
    case stale(TimeInterval)

    /// `liveElsewhere` is the kind of the first live widget on another page. Usage shows
    /// only while it is fresh, so an old figure never reads as live.
    public static func items(alerts: [String], liveElsewhere: WidgetConfig?, agentsRunning: Int,
                             networkFault: Bool, staleAge: TimeInterval?,
                             usage: UsageReading? = nil, now: Date = Date()) -> [HeaderStatus] {
        var items: [HeaderStatus] = []
        if let first = alerts.first { items.append(.alert(first, more: alerts.count - 1)) }
        if liveElsewhere != nil { items.append(.liveElsewhere) }
        if agentsRunning > 0, liveElsewhere != .agents { items.append(.agents(agentsRunning)) }
        if let usage, usage.isFresh(asOf: now, agentRunning: agentsRunning > 0),
           let fiveHour = usage.current(asOf: now).fiveHour {
            items.append(.usage(fiveHour.usedPercentage))
        }
        if networkFault { items.append(.networkFault) }
        if let staleAge { items.append(.stale(staleAge)) }
        return Array(items.prefix(3))
    }
}
