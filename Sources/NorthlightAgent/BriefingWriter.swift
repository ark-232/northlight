import Foundation
import FoundationModels
import NorthlightKit

/// Writes the TV's morning briefing with the Mac's on-device model (D10): nothing leaves
/// the Mac, and the model sees only the facts the TV sent.
public enum BriefingWriter {
    static let instructions = """
        You write the morning briefing shown on a household's TV dashboard. Use only the facts \
        given, and never add one. Say it the way a person would tell it aloud over breakfast, in \
        two to four short sentences: the weather first with the day's high and low, then the \
        alerts if the facts list any, then the day's events and their times. No greeting, lists, \
        semicolons, headings or emoji.
        """

    /// The briefing, or why the model cannot write it.
    public static func write(_ request: BriefingRequest) async -> Briefing {
        let model = SystemLanguageModel.default
        guard case .available = model.availability else {
            return .unavailable(reason: reason(model.availability), at: Date())
        }
        do {
            let response = try await LanguageModelSession(model: model, instructions: instructions).respond(to: facts(for: request))
            return .written(text: response.content.trimmingCharacters(in: .whitespacesAndNewlines), at: Date())
        } catch {
            return .unavailable(reason: "The Mac's model could not write it: \(error.localizedDescription)", at: Date())
        }
    }

    /// The request as a few plain lines, in the viewer's locale and units and the place's
    /// clock: all the model is given.
    static func facts(for request: BriefingRequest) -> String {
        let base = Locale(identifier: request.locale)
        let locale = request.units?.locale(over: base) ?? base
        let zone = request.place.timeZone
        func temperature(_ value: Measurement<UnitTemperature>) -> String {
            value.formatted(.measurement(width: .abbreviated, usage: .weather, numberFormatStyle: .number.precision(.fractionLength(0)))
                .locale(locale))
        }
        var lines = [
            "Place: \(request.place.name)",
            "Day: \(request.day.formatted(Date.FormatStyle(timeZone: zone).weekday(.wide).month(.wide).day().locale(locale)))",
        ]
        if let weather = request.weather {
            lines.append("Now: \(temperature(weather.temperature)), \(weather.condition.label.lowercased()), "
                         + "wind \(weather.windSpeed.formatted(.wind.locale(locale)))")
            if let today = weather.days.first {
                lines.append("Today: high \(temperature(today.high)), low \(temperature(today.low)), "
                             + "\(today.precipitationChance)% chance of precipitation")
            }
        }
        if !request.alerts.isEmpty {
            lines.append("Alerts: " + request.alerts.map { flat($0.event) }.joined(separator: "; "))
        }
        let time = Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone).locale(locale)
        lines.append("Agenda: " + (request.events.isEmpty ? "nothing scheduled" : request.events.map {
            $0.isAllDay ? "all day, \(flat($0.title))" : "\($0.start.formatted(time)), \(flat($0.title))"
        }.joined(separator: "; ")))
        return lines.joined(separator: "\n")
    }

    /// One line of at most 80 characters: anyone who can invite the account names an
    /// event, and a title must not add a fact of its own.
    private static func flat(_ text: String) -> String {
        String(text.split(whereSeparator: \.isWhitespace).joined(separator: " ").prefix(80))
    }

    private static func reason(_ availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .unavailable(.deviceNotEligible): "This Mac cannot run Apple Intelligence."
        case .unavailable(.appleIntelligenceNotEnabled): "Apple Intelligence is off on this Mac."
        case .unavailable(.modelNotReady): "Apple Intelligence is still getting ready on this Mac."
        default: "The Mac's model is not available."
        }
    }
}
