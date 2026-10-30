import Foundation

public struct CalendarEvent: Identifiable, Codable, Sendable, Equatable {
    public var id: String
    public var title: String
    public var location: String?
    public var start: Date
    public var end: Date
    public var isAllDay: Bool

    public init(id: String, title: String, location: String?, start: Date, end: Date, isAllDay: Bool) {
        self.id = id
        self.title = title
        self.location = location
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
    }
}

/// RFC 5545 reader, scoped deliberately to what a real Google Calendar feed emits
/// for a two-week window: VEVENT with SUMMARY/LOCATION/DTSTART/DTEND/DURATION,
/// RRULE (FREQ/INTERVAL/COUNT/UNTIL/BYDAY/BYMONTHDAY), EXDATE exclusions, and
/// RECURRENCE-ID overrides. Not implemented, because Google does not emit them
/// here: BYSETPOS, BYWEEKNO, BYYEARDAY, and VALARM.
public enum ICSParser {

    /// Expands the feed into concrete occurrences overlapping `window`.
    /// Floating and all-day times read in `calendar`'s zone, which is the place's.
    public static func parse(_ text: String, window: DateInterval, calendar: Calendar) -> [CalendarEvent] {
        let lines = unfold(text)
        var masters: [RawEvent] = []
        var overrides: [RawEvent] = []

        var current: [ContentLine]? = nil
        var depth = 0

        for line in lines {
            let upper = line.uppercased()
            if upper.hasPrefix("BEGIN:VEVENT") {
                current = []
                depth = 0
                continue
            }
            if upper.hasPrefix("END:VEVENT") {
                if let props = current, let raw = RawEvent(props, calendar: calendar) {
                    if raw.recurrenceID != nil { overrides.append(raw) } else { masters.append(raw) }
                }
                current = nil
                continue
            }
            guard current != nil else { continue }
            // Skip nested components (VALARM) so their properties don't leak into the event.
            if upper.hasPrefix("BEGIN:") { depth += 1; continue }
            if upper.hasPrefix("END:") { depth = max(0, depth - 1); continue }
            if depth == 0, let cl = ContentLine(line) { current?.append(cl) }
        }

        // An override supersedes the master instance starting at its RECURRENCE-ID.
        var supersededKeys = Set<String>()
        for o in overrides {
            if let rid = o.recurrenceID {
                supersededKeys.insert(instanceKey(uid: o.uid, start: rid))
            }
        }

        var out: [CalendarEvent] = []

        for master in masters {
            for start in master.occurrences(in: window, calendar: calendar) {
                let key = instanceKey(uid: master.uid, start: start)
                if supersededKeys.contains(key) { continue }
                if master.exdates.contains(where: { nearlyEqual($0, start) }) { continue }
                let end = start.addingTimeInterval(master.duration)
                guard overlaps(start: start, end: end, window: window) else { continue }
                out.append(CalendarEvent(
                    id: key,
                    title: master.summary,
                    location: master.location,
                    start: start,
                    end: end,
                    isAllDay: master.isAllDay
                ))
            }
        }

        for o in overrides {
            let start = o.start
            let end = start.addingTimeInterval(o.duration)
            guard overlaps(start: start, end: end, window: window) else { continue }
            // Keyed by the ORIGINAL recurrence slot, which is what the master's
            // instance would have been — that is what makes supersession work.
            let key = instanceKey(uid: o.uid, start: o.recurrenceID ?? start)
            out.append(CalendarEvent(
                id: key,
                title: o.summary,
                location: o.location,
                start: start,
                end: end,
                isAllDay: o.isAllDay
            ))
        }

        // Stable ordering: all-day first within a day, then by start, then title.
        return out.sorted {
            if $0.start != $1.start { return $0.start < $1.start }
            if $0.isAllDay != $1.isAllDay { return $0.isAllDay }
            return $0.title < $1.title
        }
    }

    static func instanceKey(uid: String, start: Date) -> String {
        "\(uid)@\(Int(start.timeIntervalSince1970))"
    }

    static func overlaps(start: Date, end: Date, window: DateInterval) -> Bool {
        // A zero-length event at exactly window.end still counts as inside.
        start <= window.end && end >= window.start
    }

    static func nearlyEqual(_ a: Date, _ b: Date) -> Bool {
        abs(a.timeIntervalSince(b)) < 1
    }

    // MARK: - Line unfolding

    /// RFC 5545 folds long lines by inserting CRLF + a single space or tab. This
    /// must run before anything else or every folded SUMMARY and RRULE is corrupt.
    static func unfold(_ text: String) -> [String] {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var out: [String] = []
        for raw in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if let first = raw.first, first == " " || first == "\t" {
                let continuation = String(raw.dropFirst())
                if out.isEmpty { out.append(continuation) } else { out[out.count - 1] += continuation }
            } else {
                out.append(String(raw))
            }
        }
        return out.filter { !$0.isEmpty }
    }
}

// MARK: - Content line

struct ContentLine {
    var name: String
    var params: [String: String]
    var value: String

    init?(_ line: String) {
        // The first colon outside double quotes separates name+params from value.
        var inQuotes = false
        var splitIndex: String.Index? = nil
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if c == "\"" { inQuotes.toggle() }
            else if c == ":" && !inQuotes { splitIndex = i; break }
            i = line.index(after: i)
        }
        guard let idx = splitIndex else { return nil }

        let head = String(line[line.startIndex..<idx])
        self.value = String(line[line.index(after: idx)...])

        let parts = ContentLine.splitUnquoted(head, on: ";")
        guard let first = parts.first, !first.isEmpty else { return nil }
        self.name = first.uppercased()

        var p: [String: String] = [:]
        for param in parts.dropFirst() {
            let kv = ContentLine.splitUnquoted(param, on: "=")
            guard kv.count >= 2 else { continue }
            let key = kv[0].uppercased()
            var v = kv[1...].joined(separator: "=")
            if v.hasPrefix("\"") && v.hasSuffix("\"") && v.count >= 2 {
                v = String(v.dropFirst().dropLast())
            }
            p[key] = v
        }
        self.params = p
    }

    static func splitUnquoted(_ s: String, on sep: Character) -> [String] {
        var out: [String] = []
        var cur = ""
        var inQuotes = false
        for c in s {
            if c == "\"" { inQuotes.toggle(); cur.append(c); continue }
            if c == sep && !inQuotes { out.append(cur); cur = ""; continue }
            cur.append(c)
        }
        out.append(cur)
        return out
    }

    /// TEXT-valued properties escape commas, semicolons, newlines and backslashes.
    var unescapedValue: String {
        var out = ""
        var iter = value.makeIterator()
        while let c = iter.next() {
            guard c == "\\" else { out.append(c); continue }
            guard let next = iter.next() else { out.append(c); break }
            switch next {
            case "n", "N": out.append("\n")
            case ",": out.append(",")
            case ";": out.append(";")
            case "\\": out.append("\\")
            default: out.append(next)
            }
        }
        return out
    }
}

// MARK: - Raw event

struct RawEvent {
    var uid: String
    var summary: String
    var location: String?
    var start: Date
    var duration: TimeInterval
    var isAllDay: Bool
    var timeZone: TimeZone
    var rrule: [String: String]
    var exdates: [Date]
    var recurrenceID: Date?

    init?(_ props: [ContentLine], calendar: Calendar) {
        var uid: String? = nil
        var summary = "(no title)"
        var location: String? = nil
        var dtstart: ParsedDate? = nil
        var dtend: ParsedDate? = nil
        var durationString: String? = nil
        var rrule: [String: String] = [:]
        var exdates: [Date] = []
        var recurrenceID: Date? = nil

        for p in props {
            switch p.name {
            case "UID": uid = p.value
            case "SUMMARY": summary = p.unescapedValue
            case "LOCATION":
                let l = p.unescapedValue
                location = l.isEmpty ? nil : l
            case "DTSTART": dtstart = ParsedDate(p, defaultZone: calendar.timeZone)
            case "DTEND": dtend = ParsedDate(p, defaultZone: calendar.timeZone)
            case "DURATION": durationString = p.value
            case "RRULE":
                for pair in p.value.split(separator: ";") {
                    let kv = pair.split(separator: "=", maxSplits: 1)
                    if kv.count == 2 { rrule[kv[0].uppercased()] = String(kv[1]) }
                }
            case "EXDATE":
                // EXDATE can carry a comma-separated list on one line.
                for piece in p.value.split(separator: ",") {
                    if let d = ParsedDate(value: String(piece), params: p.params, defaultZone: calendar.timeZone) { exdates.append(d.date) }
                }
            case "RECURRENCE-ID": recurrenceID = ParsedDate(p, defaultZone: calendar.timeZone)?.date
            default: break
            }
        }

        guard let uid, let dtstart else { return nil }
        self.uid = uid
        self.summary = summary
        self.location = location
        self.start = dtstart.date
        self.isAllDay = dtstart.isDateOnly
        self.timeZone = dtstart.timeZone
        self.rrule = rrule
        self.exdates = exdates
        self.recurrenceID = recurrenceID

        if let dtend {
            self.duration = max(0, dtend.date.timeIntervalSince(dtstart.date))
        } else if let durationString, let d = RawEvent.parseDuration(durationString) {
            self.duration = d
        } else if dtstart.isDateOnly {
            self.duration = 86_400
        } else {
            self.duration = 0
        }
    }

    /// ISO 8601 duration, the subset iCalendar uses: P[nW][nD][T[nH][nM][nS]].
    static func parseDuration(_ s: String) -> TimeInterval? {
        var body = s
        var sign: Double = 1
        if body.hasPrefix("-") { sign = -1; body.removeFirst() }
        else if body.hasPrefix("+") { body.removeFirst() }
        guard body.hasPrefix("P") else { return nil }
        body.removeFirst()

        var total: Double = 0
        var number = ""
        var inTime = false
        for c in body {
            if c == "T" { inTime = true; number = ""; continue }
            if c.isNumber { number.append(c); continue }
            let n = Double(number) ?? 0
            switch c {
            case "W": total += n * 604_800
            case "D": total += n * 86_400
            case "H": total += n * 3_600
            case "M": total += inTime ? n * 60 : n * 86_400 * 30
            case "S": total += n
            default: return nil
            }
            number = ""
        }
        return sign * total
    }

    // MARK: Recurrence expansion

    /// Hard ceiling so a malformed or very old daily rule cannot spin.
    static let iterationCap = 20_000

    func occurrences(in window: DateInterval, calendar baseCalendar: Calendar) -> [Date] {
        var cal = baseCalendar
        cal.timeZone = timeZone

        guard let freq = rrule["FREQ"]?.uppercased(), !freq.isEmpty else {
            return [start]
        }

        let interval = max(1, Int(rrule["INTERVAL"] ?? "") ?? 1)
        let limitCount = Int(rrule["COUNT"] ?? "")
        let until: Date? = rrule["UNTIL"].flatMap { ParsedDate(value: $0, params: [:], defaultZone: baseCalendar.timeZone)?.date }
        let byDay = (rrule["BYDAY"] ?? "").split(separator: ",").compactMap { OrdinalWeekday(String($0)) }
        let byMonthDay = (rrule["BYMONTHDAY"] ?? "").split(separator: ",").compactMap { Int($0) }

        let timeOfDay = cal.dateComponents([.hour, .minute, .second], from: start)
        var emitted = 0
        var results: [Date] = []
        var iterations = 0

        // `block` walks forward one FREQ period at a time; each block yields zero
        // or more candidate instants. COUNT is measured from DTSTART, which is why
        // iteration always begins there rather than at the window.
        var block = 0
        outer: while iterations < RawEvent.iterationCap {
            iterations += 1
            var candidates: [Date] = []

            switch freq {
            case "DAILY":
                if let d = cal.date(byAdding: .day, value: block * interval, to: start) { candidates = [d] }

            case "WEEKLY":
                guard let weekBase = cal.date(byAdding: .weekOfYear, value: block * interval, to: start) else { break }
                if byDay.isEmpty {
                    candidates = [weekBase]
                } else {
                    guard let weekStart = cal.dateInterval(of: .weekOfYear, for: weekBase)?.start else { break }
                    for od in byDay {
                        guard let day = cal.nextDate(
                            after: weekStart.addingTimeInterval(-1),
                            matching: DateComponents(weekday: od.weekday),
                            matchingPolicy: .nextTime,
                            direction: .forward
                        ) else { continue }
                        if let withTime = apply(timeOfDay, to: day, cal: cal) { candidates.append(withTime) }
                    }
                }

            case "MONTHLY":
                guard let monthBase = cal.date(byAdding: .month, value: block * interval, to: start) else { break }
                if !byMonthDay.isEmpty {
                    for md in byMonthDay {
                        if let d = dayOfMonth(md, in: monthBase, cal: cal),
                           let withTime = apply(timeOfDay, to: d, cal: cal) { candidates.append(withTime) }
                    }
                } else if !byDay.isEmpty {
                    for od in byDay {
                        if let d = nthWeekday(od, in: monthBase, cal: cal),
                           let withTime = apply(timeOfDay, to: d, cal: cal) { candidates.append(withTime) }
                    }
                } else {
                    candidates = [monthBase]
                }

            case "YEARLY":
                if let d = cal.date(byAdding: .year, value: block * interval, to: start) { candidates = [d] }

            default:
                return [start]
            }

            if candidates.isEmpty && freq != "WEEKLY" && freq != "MONTHLY" { break }

            for c in candidates.sorted() {
                if c < start { continue }
                if let until, c > until { break outer }
                if let limitCount, emitted >= limitCount { break outer }
                emitted += 1
                if c > window.end { break outer }
                if c.addingTimeInterval(duration) >= window.start { results.append(c) }
            }

            // Termination is handled inside the candidate loop: the first instant
            // past window.end breaks `outer`. Only block 0 can yield candidates
            // earlier than DTSTART, so skipping those cannot loop forever.
            block += 1
        }

        return results
    }

    private func apply(_ time: DateComponents, to day: Date, cal: Calendar) -> Date? {
        if isAllDay { return cal.startOfDay(for: day) }
        var comps = cal.dateComponents([.year, .month, .day], from: day)
        comps.hour = time.hour
        comps.minute = time.minute
        comps.second = time.second
        return cal.date(from: comps)
    }

    private func dayOfMonth(_ md: Int, in monthBase: Date, cal: Calendar) -> Date? {
        guard let range = cal.range(of: .day, in: .month, for: monthBase) else { return nil }
        let day = md > 0 ? md : range.count + md + 1
        guard day >= 1, day <= range.count else { return nil }
        var comps = cal.dateComponents([.year, .month], from: monthBase)
        comps.day = day
        return cal.date(from: comps)
    }

    private func nthWeekday(_ od: OrdinalWeekday, in monthBase: Date, cal: Calendar) -> Date? {
        var comps = cal.dateComponents([.year, .month], from: monthBase)
        comps.day = 1
        guard let first = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: monthBase) else { return nil }

        var matches: [Date] = []
        for offset in 0..<range.count {
            guard let d = cal.date(byAdding: .day, value: offset, to: first) else { continue }
            if cal.component(.weekday, from: d) == od.weekday { matches.append(d) }
        }
        guard !matches.isEmpty else { return nil }
        guard let ordinal = od.ordinal else { return matches.first }
        let index = ordinal > 0 ? ordinal - 1 : matches.count + ordinal
        guard index >= 0, index < matches.count else { return nil }
        return matches[index]
    }
}

/// A BYDAY entry: "TU", "3TU", "-1FR".
struct OrdinalWeekday {
    var ordinal: Int?
    var weekday: Int

    static let map: [String: Int] = ["SU": 1, "MO": 2, "TU": 3, "WE": 4, "TH": 5, "FR": 6, "SA": 7]

    init?(_ s: String) {
        let token = s.trimmingCharacters(in: .whitespaces).uppercased()
        guard token.count >= 2 else { return nil }
        let code = String(token.suffix(2))
        guard let wd = OrdinalWeekday.map[code] else { return nil }
        self.weekday = wd
        let prefix = String(token.dropLast(2))
        self.ordinal = prefix.isEmpty ? nil : Int(prefix)
    }
}

/// A DATE or DATE-TIME value plus the zone it should be read in.
struct ParsedDate {
    var date: Date
    var isDateOnly: Bool
    var timeZone: TimeZone

    init?(_ line: ContentLine, defaultZone: TimeZone) {
        self.init(value: line.value, params: line.params, defaultZone: defaultZone)
    }

    /// `defaultZone` applies to floating times and dates, which carry no zone.
    init?(value: String, params: [String: String], defaultZone: TimeZone) {
        let raw = value.trimmingCharacters(in: .whitespaces)
        let zone: TimeZone
        if raw.hasSuffix("Z") {
            zone = TimeZone(identifier: "UTC")!
        } else if let tzid = params["TZID"], let tz = TimeZone(identifier: tzid) {
            zone = tz
        } else {
            zone = defaultZone
        }
        self.timeZone = zone

        let isDate = params["VALUE"]?.uppercased() == "DATE" || raw.count == 8
        self.isDateOnly = isDate

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone

        if isDate {
            guard raw.count >= 8,
                  let y = Int(raw.prefix(4)),
                  let m = Int(raw.dropFirst(4).prefix(2)),
                  let d = Int(raw.dropFirst(6).prefix(2)),
                  let date = cal.date(from: DateComponents(year: y, month: m, day: d))
            else { return nil }
            self.date = date
            return
        }

        let body = raw.hasSuffix("Z") ? String(raw.dropLast()) : raw
        let parts = body.split(separator: "T")
        guard parts.count == 2, parts[0].count == 8, parts[1].count >= 6,
              let y = Int(parts[0].prefix(4)),
              let m = Int(parts[0].dropFirst(4).prefix(2)),
              let d = Int(parts[0].dropFirst(6).prefix(2)),
              let hh = Int(parts[1].prefix(2)),
              let mm = Int(parts[1].dropFirst(2).prefix(2)),
              let ss = Int(parts[1].dropFirst(4).prefix(2)),
              let date = cal.date(from: DateComponents(year: y, month: m, day: d, hour: hh, minute: mm, second: ss))
        else { return nil }
        self.date = date
    }
}
