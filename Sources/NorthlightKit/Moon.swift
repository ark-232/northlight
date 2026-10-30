import Foundation

/// Moon phase from the mean synodic cycle. Accurate to a few hours, which is far
/// inside what a dashboard needs, and avoids pulling in an ephemeris or a network
/// call for something that is pure arithmetic.
public struct Moon: Codable, Sendable, Equatable {
    /// Days since the last new moon, 0..<29.53.
    public var age: Double
    /// Illuminated fraction, 0...1.
    public var illumination: Double
    public var name: String
    public var symbol: String

    public static let synodicMonth: Double = 29.530588853

    /// New moon of 6 January 2000, 18:14 UTC — the standard epoch for this method.
    static let referenceNewMoon = Date(timeIntervalSince1970: 947_182_440)

    public init(date: Date = Date()) {
        let elapsedDays = date.timeIntervalSince(Moon.referenceNewMoon) / 86_400
        var cycles = elapsedDays / Moon.synodicMonth
        cycles -= cycles.rounded(.down)
        if cycles < 0 { cycles += 1 }

        self.age = cycles * Moon.synodicMonth
        // Illumination follows the phase angle, peaking at full moon (mid-cycle).
        self.illumination = (1 - cos(2 * .pi * cycles)) / 2

        let (name, symbol) = Moon.describe(cycles)
        self.name = name
        self.symbol = symbol
    }

    /// Named by eighths of the cycle, with the four exact phases given a narrow
    /// window so "full moon" means roughly the night it is full.
    static func describe(_ cycles: Double) -> (String, String) {
        let window = 0.02
        switch cycles {
        case ..<window: return ("New moon", "moonphase.new.moon")
        case ..<(0.25 - window): return ("Waxing crescent", "moonphase.waxing.crescent")
        case ..<(0.25 + window): return ("First quarter", "moonphase.first.quarter")
        case ..<(0.5 - window): return ("Waxing gibbous", "moonphase.waxing.gibbous")
        case ..<(0.5 + window): return ("Full moon", "moonphase.full.moon")
        case ..<(0.75 - window): return ("Waning gibbous", "moonphase.waning.gibbous")
        case ..<(0.75 + window): return ("Last quarter", "moonphase.last.quarter")
        case ..<(1 - window): return ("Waning crescent", "moonphase.waning.crescent")
        default: return ("New moon", "moonphase.new.moon")
        }
    }
}

extension Double {
    /// Seconds as "9h 47m" — for daylight length, which is the number that
    /// actually matters at this latitude.
    public var hoursMinutes: String {
        let total = Int(self.rounded())
        return "\(total / 3_600)h \((total % 3_600) / 60)m"
    }

    /// Signed seconds as "−5m 42s", for day-over-day daylight change.
    public var signedMinutesSeconds: String {
        let total = Int(abs(self).rounded())
        let sign = self < 0 ? "−" : "+"
        let minutes = total / 60
        let seconds = total % 60
        return minutes > 0 ? "\(sign)\(minutes)m \(seconds)s" : "\(sign)\(seconds)s"
    }
}
