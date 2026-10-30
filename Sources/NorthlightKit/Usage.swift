import Foundation

/// The Claude account's 5-hour and 7-day usage, as Claude Code last saw it: the file the
/// statusLine wrapper writes on the Mac, and the frame the Mac pushes to the TV. Either
/// window may be missing. Times are epoch seconds both in the file and on the bridge.
public struct UsageReading: Codable, Sendable, Equatable {
    public struct Window: Codable, Sendable, Equatable {
        public var usedPercentage: Double
        public var resetsAt: Date

        public init(usedPercentage: Double, resetsAt: Date) {
            self.usedPercentage = usedPercentage
            self.resetsAt = resetsAt
        }

        private enum CodingKeys: String, CodingKey {
            case usedPercentage = "used_percentage", resetsAt = "resets_at"
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            usedPercentage = try container.decode(Double.self, forKey: .usedPercentage)
            resetsAt = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .resetsAt))
        }

        public func encode(to encoder: any Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(usedPercentage, forKey: .usedPercentage)
            try container.encode(resetsAt.timeIntervalSince1970, forKey: .resetsAt)
        }

        /// "42 %"
        public var percent: String { "\(Int(usedPercentage.rounded())) %" }

        /// "7:10 PM" within a day, "Thu" after.
        public func resets(now: Date, timeZone: TimeZone, locale: Locale = .autoupdatingCurrent) -> String {
            resetsAt.timeIntervalSince(now) < 86_400
                ? resetsAt.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone))
                : resetsAt.formatted(Date.FormatStyle(locale: locale, timeZone: timeZone).weekday(.abbreviated))
        }

        /// "5 h 42 % · resets 7:10 PM"
        public func line(_ name: String, now: Date, timeZone: TimeZone, locale: Locale = .autoupdatingCurrent) -> String {
            "\(name) \(percent) · resets \(resets(now: now, timeZone: timeZone, locale: locale))"
        }
    }

    public enum Level: Sendable {
        case normal, warning, critical

        public init(_ percentage: Double) {
            self = percentage >= 90 ? .critical : percentage >= 70 ? .warning : .normal
        }
    }

    /// How long a reading counts as current with no agent running.
    public static let freshFor: TimeInterval = 15 * 60

    public var fiveHour: Window?
    public var sevenDay: Window?
    public var observedAt: Date

    public init(fiveHour: Window?, sevenDay: Window?, observedAt: Date) {
        self.fiveHour = fiveHour
        self.sevenDay = sevenDay
        self.observedAt = observedAt
    }

    private enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour", sevenDay = "seven_day", observedAt = "observed_at"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        fiveHour = try container.decodeIfPresent(Window.self, forKey: .fiveHour)
        sevenDay = try container.decodeIfPresent(Window.self, forKey: .sevenDay)
        observedAt = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .observedAt))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(fiveHour, forKey: .fiveHour)
        try container.encodeIfPresent(sevenDay, forKey: .sevenDay)
        try container.encode(observedAt.timeIntervalSince1970, forKey: .observedAt)
    }

    /// The windows that have not reset since the reading.
    public func current(asOf now: Date) -> UsageReading {
        UsageReading(fiveHour: fiveHour.flatMap { $0.resetsAt > now ? $0 : nil },
                     sevenDay: sevenDay.flatMap { $0.resetsAt > now ? $0 : nil },
                     observedAt: observedAt)
    }

    public var isEmpty: Bool { fiveHour == nil && sevenDay == nil }

    public func isFresh(asOf now: Date, agentRunning: Bool) -> Bool {
        agentRunning || now.timeIntervalSince(observedAt) < Self.freshFor
    }
}
