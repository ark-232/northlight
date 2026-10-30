import SwiftUI
import NorthlightKit

struct AgendaTile: View {
    /// Nil when no calendar is set.
    let feed: Loaded<[CalendarEvent]>?
    let now: Date
    @Environment(\.calendar) private var calendar
    @Environment(\.widgetSize) private var size

    private func grouped(_ events: [CalendarEvent]) -> [(day: Date, events: [CalendarEvent])] {
        let upcoming = events.filter { $0.end >= now }
        let buckets = Dictionary(grouping: upcoming) { calendar.startOfDay(for: $0.start) }
        return buckets.keys.sorted().map { ($0, buckets[$0]!.sorted { $0.start < $1.start }) }
    }

    /// The days that fit in `lines`, a day's label and each event taking one line.
    private func fitted(_ groups: [(day: Date, events: [CalendarEvent])], lines: Int) -> [(day: Date, events: [CalendarEvent])] {
        var left = lines
        var shown: [(day: Date, events: [CalendarEvent])] = []
        for group in groups where left >= 2 {
            let events = Array(group.events.prefix(left - 1))
            shown.append((group.day, events))
            left -= 1 + events.count
        }
        return shown
    }

    var body: some View {
        Tile(label: "Agenda", accent: Theme.Palette.violet, trailing: feed?.trailing(asOf: now)) {
            if let feed {
                FeedBody(state: feed.state(asOf: now)) { events in
                    let groups = grouped(events)
                    if groups.isEmpty {
                        TilePlaceholder(text: "Nothing scheduled")
                    } else {
                        VStack(alignment: .leading, spacing: 22) {
                            ForEach(fitted(groups, lines: size == .large ? 12 : 5), id: \.day) { group in
                                VStack(alignment: .leading, spacing: 12) {
                                    Text(dayLabel(group.day))
                                        .font(Theme.Font.label)
                                        .tracking(1.2)
                                        .foregroundStyle(Theme.Palette.faint)
                                    ForEach(group.events) { event in
                                        AgendaRow(event: event, isNow: isHappening(event))
                                    }
                                }
                            }
                        }
                    }
                }
            } else {
                TilePlaceholder(text: "No calendar set")
            }
        }
    }

    private func isHappening(_ event: CalendarEvent) -> Bool {
        !event.isAllDay && event.start <= now && event.end > now
    }

    private func dayLabel(_ day: Date) -> String {
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInTomorrow(day) { return "Tomorrow" }
        return day.formatted(Date.FormatStyle(timeZone: calendar.timeZone).weekday(.wide).month(.abbreviated).day())
    }
}

private struct AgendaRow: View {
    let event: CalendarEvent
    let isNow: Bool
    @Environment(\.timeZone) private var zone

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            RoundedRectangle(cornerRadius: 2)
                .fill(isNow ? Theme.Palette.green : Theme.Palette.hairline)
                .frame(width: 4, height: 38)

            Text(event.isAllDay ? "all day" : event.start.formatted(Date.FormatStyle(date: .omitted, time: .shortened, timeZone: zone)))
                .font(Theme.Font.bodySmall)
                .monospacedDigit()
                .foregroundStyle(isNow ? Theme.Palette.green : Theme.Palette.muted)
                .frame(width: 150, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(Theme.Font.body)
                    .foregroundStyle(Theme.Palette.bone)
                    .lineLimit(1)
                if let location = event.location {
                    Text(location)
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.Palette.faint)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
    }
}
