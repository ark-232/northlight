import Foundation

extension HTTP {
    /// Fetches and expands a Google Calendar private iCal feed.
    ///
    /// tvOS has no EventKit calendar access, so this is the only route to the
    /// calendar. The URL is a bearer secret: anyone holding it can read the
    /// calendar, which is why it is never logged and never leaves the device.
    public func calendar(
        icsURL: URL,
        calendar: Calendar,
        days: Int = 14,
        now: Date = Date()
    ) async throws -> [CalendarEvent] {
        let body = try await text(icsURL)
        return ICSParser.parse(body, window: try .agenda(days: days, calendar: calendar, now: now), calendar: calendar)
    }
}

extension DateInterval {
    /// What the agenda shows: from the start of today for `days` days, in `calendar`.
    public static func agenda(days: Int = 14, calendar: Calendar, now: Date = Date()) throws -> DateInterval {
        let start = calendar.startOfDay(for: now)
        guard let end = calendar.date(byAdding: .day, value: days, to: start) else {
            throw FeedError.decode("could not build the expansion window")
        }
        return DateInterval(start: start, end: end)
    }
}

/// The feed URL for a pasted calendar address. Calendar apps hand out webcal://
/// links for the same feed over https.
public func calendarFeedURL(from entry: String) -> URL? {
    var text = entry.trimmingCharacters(in: .whitespacesAndNewlines)
    if text.lowercased().hasPrefix("webcal://") {
        text = "https://" + text.dropFirst("webcal://".count)
    }
    guard let url = URL(string: text),
          let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
          let host = url.host(), !host.isEmpty
    else { return nil }
    return url
}

extension CalendarEvent {
    /// Every source's events by start, each occurrence once: one calendar can be
    /// reached by its .ics address and through iCloud.
    static func merged(_ sources: [[CalendarEvent]]) -> [CalendarEvent] {
        var seen = Set<String>()
        return sources.joined().filter { seen.insert($0.id).inserted }.sorted { $0.start < $1.start }
    }
}
