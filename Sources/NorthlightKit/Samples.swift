import Foundation

/// Plausible readings for SwiftUI previews and the Mac editor: Reykjavík on an
/// October evening, dated relative to `now`.
public enum Samples {
    public static let place = Place(name: "Reykjavík", latitude: 64.1466, longitude: -21.9426,
                                    timeZoneIdentifier: "Atlantic/Reykjavik", countryCode: "IS")

    public static func weather(at now: Date) -> Weather {
        let today = place.calendar.startOfDay(for: now)
        let highs = [4.5, 3.0, 1.5, 0.5, 2.0, 3.5, 1.0], lows = [-1.5, -2.5, -4.0, -5.5, -3.0, -1.0, -3.5]
        let codes = [3, 71, 73, 71, 2, 1, 3], chances = [20, 60, 80, 45, 10, 5, 15]
        let snowfall = [0, 1.2, 3.4, 0.8, 0, 0, 0]
        let days = (0..<7).map { i in
            Weather.Day(date: place.calendar.date(byAdding: .day, value: i, to: today)!,
                        high: Measurement(value: highs[i], unit: .celsius), low: Measurement(value: lows[i], unit: .celsius),
                        code: codes[i], precipitationChance: chances[i],
                        snowfall: Measurement(value: snowfall[i], unit: .centimeters))
        }
        return Weather(temperature: Measurement(value: 2.4, unit: .celsius), apparent: Measurement(value: -1.5, unit: .celsius),
                       code: 3, windSpeed: Measurement(value: 14, unit: .kilometersPerHour), humidity: 78, isDay: false,
                       cloudCover: 90, days: days, snowDepth: Measurement(value: 0.05, unit: .meters))
    }

    public static func aurora(at now: Date) -> Aurora {
        Aurora(kp: 4.3, kpObserved: now.addingTimeInterval(-900), localProbability: 38, forecastTime: now)
    }

    public static func quakes(at now: Date) -> [Quake] {
        [
            (3.6, "6 km NE of Grindavík, Iceland", 2.0), (2.8, "14 km E of Hveragerði, Iceland", 9.0),
            (4.1, "Reykjanes Ridge", 20.0), (2.6, "9 km N of Hella, Iceland", 36.0),
            (2.5, "22 km SE of Vík, Iceland", 53.0), (3.1, "31 km E of Grímsey, Iceland", 70.0),
        ].enumerated().map { i, quake in
            Quake(id: "sample\(i)", magnitude: quake.0, place: quake.1,
                  time: now.addingTimeInterval(-quake.2 * 3_600), depthKm: 40)
        }
    }

    public static func events(at now: Date) -> [CalendarEvent] {
        let calendar = place.calendar
        let today = calendar.startOfDay(for: now)
        func at(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
            calendar.date(byAdding: DateComponents(day: day, hour: hour, minute: minute), to: today)!
        }
        return [
            CalendarEvent(id: "s1", title: "Team standup", location: nil, start: at(0, 9), end: at(0, 9, 15), isAllDay: false),
            CalendarEvent(id: "s2", title: "Dentist", location: "Downtown", start: at(0, 15, 30), end: at(0, 16, 30), isAllDay: false),
            CalendarEvent(id: "s3", title: "Book club", location: nil, start: at(0, 19), end: at(0, 21), isAllDay: false),
            CalendarEvent(id: "s4", title: "Trash day", location: nil, start: at(1, 0), end: at(2, 0), isAllDay: true),
            CalendarEvent(id: "s5", title: "Flight to Oslo", location: "KEF", start: at(1, 7, 45), end: at(1, 11, 30), isAllDay: false),
            CalendarEvent(id: "s6", title: "Climbing gym", location: nil, start: at(2, 18), end: at(2, 20), isAllDay: false),
        ]
    }

    public static let airQuality = AirQuality(usAQI: 18, pm25: 3.2, pm10: 5.1)

    public static let network = NetworkPath(link: .ethernet, quality: .good, gateway: "192.168.1.1", address: "192.168.1.42")

    /// Three hours of probes, so the monitor reads "since" its first: the internet near
    /// 38 ms with an evening bump and one failure, the gateway near 2 ms.
    public static func latency(at now: Date) -> LatencyHistory {
        var history = LatencyHistory()
        let count = 360
        for index in 0..<count {
            let date = now.addingTimeInterval(Double(index - count + 1) * 30)
            let wave = sin(Double(index) / 9) * 3 + sin(Double(index) / 2.3) * 1.5
            let bump = (200..<230).contains(index) ? 30.0 : 0
            history.record(LatencySample(date: date, milliseconds: index == 290 ? nil : 38 + wave + bump), to: .internet)
            history.record(LatencySample(date: date, milliseconds: 2.2 + sin(Double(index) / 3) * 0.6), to: .gateway)
        }
        return history
    }

    /// A week of tests, the last of them `speed(at:)`.
    public static func speedTests(at now: Date) -> [SpeedResult] {
        let earlier = (1..<12).map { index in
            SpeedResult(date: now.addingTimeInterval(-2 * 3_600 - Double(index) * 13 * 3_600), server: "Seattle, US",
                        downloadMegabits: 380 + sin(Double(index)) * 40, uploadMegabits: 36 + cos(Double(index)) * 4,
                        idleLatency: 20, loadedLatency: 45 + Double(index % 3) * 6)
        }
        return earlier.reversed() + [speed(at: now)]
    }

    /// A finished test's curves: the download climbing to `speed(at:)`'s, then the upload.
    public static let throughput: [ThroughputPoint] = {
        let steps = (1...40).map { Double($0) * 0.25 }
        let down = steps.map { ThroughputPoint(direction: .download, seconds: $0, megabits: 412.6 * (1 - exp(-$0 / 1.2))) }
        let up = steps.map { ThroughputPoint(direction: .upload, seconds: $0, megabits: 38.2 * (1 - exp(-$0 / 0.8))) }
        return down + up
    }()
    /// A fast, southward wind and an M1 flare an hour and a half ago over a B-class Sun.
    public static func spaceWeather(at now: Date) -> SpaceWeather {
        SpaceWeather(wind: .init(speed: 548, bz: -7, at: now.addingTimeInterval(-120)),
                     currentClass: flareClassNow(xrays(at: now)),
                     flare: .init(peakClass: "M1.0", peak: now.addingTimeInterval(-89 * 60), end: now.addingTimeInterval(-70 * 60)),
                     scales: .init(r: 1, s: 0, g: 1))
    }

    /// Six hours of a B-class Sun with that flare in them.
    public static func xrays(at now: Date) -> [SpaceWeather.XRay] {
        (0..<360).map { minute in
            let t = Double(minute)
            let flare = 9e-6 * exp(-pow((t - 270) / 12, 2))
            return SpaceWeather.XRay(time: now.addingTimeInterval((t - 359) * 60), flux: 4e-7 + 1.5e-7 * sin(t / 40) + flare)
        }
    }

    private static func flareClassNow(_ xrays: [SpaceWeather.XRay]) -> String? {
        xrays.last.map { SpaceWeather.flareClass(flux: $0.flux) }
    }

    /// The last 50 minutes of a 51.6° orbit, one fix a minute, the Earth turning under it.
    public static func iss(at now: Date) -> ISSTrack {
        (0...50).reduce(ISSTrack()) { track, minute in
            let phase = Double(minute - 50) / 92.7 * 2 * .pi + 0.9
            var longitude = 120 + Double(minute - 50) * (360 / 92.7 - 0.25) + 20 * sin(2 * phase)
            if longitude > 180 { longitude -= 360 }
            return track.adding(ISSFix(latitude: 51.6 * sin(phase), longitude: longitude, altitudeKM: 421.8, velocityKMH: 27_571,
                                       sunlit: minute > 12, time: now.addingTimeInterval(Double(minute - 50) * 60)))
        }
    }

    public static func launches(at now: Date) -> [Launch] {
        [
            ("Starlink Group 15-15", "Falcon 9", "SpaceX", "SLC-4E", "Vandenberg SFB, CA, USA", 2.3, "SEC", "Go"),
            ("We're Not Hawking Around", "Electron", "Rocket Lab", "LC-1A", "Mahia Peninsula, New Zealand", 9.8, "MIN", "Go"),
            ("Unknown Payload", "Ceres-1S", "Galactic Energy", "Rizhao offshore", "Haiyang Oriental Spaceport", 23.5, "HR", "TBC"),
            ("Bandwagon 6", "Falcon 9", "SpaceX", "SLC-40", "Cape Canaveral SFS, FL, USA", 31, "MIN", "Go"),
            ("Progress MS-34", "Soyuz 2.1a", "Roscosmos", "Site 31/6", "Baikonur Cosmodrome, Kazakhstan", 52, "SEC", "Go"),
            ("New Glenn NG-4", "New Glenn", "Blue Origin", "LC-36", "Cape Canaveral SFS, FL, USA", 96, "DAY", "TBD"),
        ].enumerated().map { i, l in
            Launch(id: "sample\(i)", mission: l.0, rocket: l.1, provider: l.2, pad: l.3, location: l.4,
                   net: now.addingTimeInterval(l.5 * 3_600), precision: l.6, status: l.7)
        }
    }

    public static let serviceStatus = [
        ServiceStatus(service: "GitHub", indicator: .none, summary: "All Systems Operational", incident: nil),
        ServiceStatus(service: "Claude", indicator: .minor, summary: "Minor Service Outage", incident: "Elevated errors on Claude Code"),
    ]

    public static func kev(at now: Date) -> KEVCatalog {
        let today = KEVParsing.utc.startOfDay(for: now)
        let entries = [("CVE-2026-102764", "BeyondTrust", "Remote Support", 1), ("CVE-2025-61624", "Fortinet", "FortiOS", 1),
                       ("CVE-2026-21589", "Atlassian", "Confluence Data Center", 2), ("CVE-2026-0322", "Palo Alto Networks", "PAN-OS", 3),
                       ("CVE-2026-104935", "Ivanti", "Connect Secure", 9)]
        return KEVCatalog(count: 1_748, recent: entries.map {
            KEVEntry(cve: $0.0, vendor: $0.1, product: $0.2, added: today.addingTimeInterval(-Double($0.3) * 86_400))
        })
    }

    /// A week of bitcoin drifting up through $82,000.
    public static func crypto(at now: Date) -> CryptoMarket {
        let hourly = (0..<168).map { hour in
            let t = Double(hour)
            return CryptoMarket.Point(time: now.addingTimeInterval((t - 167) * 3_600),
                                      price: 79_400 + 16 * t + 900 * sin(t / 11) + 350 * sin(t / 2.7))
        }
        return CryptoMarket(quotes: [CryptoQuote(symbol: "BTC", price: hourly.last!.price, open: 81_843),
                                     CryptoQuote(symbol: "ETH", price: 2_398.4, open: 2_405.43)],
                            bitcoinHourly: hourly)
    }

    public static let rates = ExchangeRates(day: "2026-10-19", perDollar: [.init(code: "EUR", rate: 0.89087),
                                                                           .init(code: "GBP", rate: 0.75016),
                                                                           .init(code: "JPY", rate: 158.24)])

    public static func hackerNews(at now: Date) -> [HNStory] {
        [
            ("OpenBSD 8.0", 412, 187, 3.1), ("Show HN: A wall dashboard for the Apple TV", 268, 94, 5.4),
            ("The physics of a solar flare, explained with one equation", 199, 61, 2.2),
            ("SQLite's new query planner", 154, 72, 7.9), ("Why the ISS needs reboosting", 98, 33, 1.3),
        ].enumerated().map { i, s in
            HNStory(id: 1_000 + i, title: s.0, points: s.1, comments: s.2, time: now.addingTimeInterval(-s.3 * 3_600))
        }
    }


    public static func briefing(at now: Date) -> Briefing {
        .written(text: "Light snow until noon, then clearing, with a high of minus two. Standup is at nine thirty and "
                     + "the dentist at three. Aurora chances climb after dark if the sky stays clear.",
                 at: Calendar.current.startOfDay(for: now).addingTimeInterval(5 * 3_600 + 12 * 60))
    }

    public static func speed(at now: Date) -> SpeedResult {
        SpeedResult(date: now.addingTimeInterval(-2 * 3_600), server: "Seattle, US", downloadMegabits: 412.6,
                    uploadMegabits: 38.2, idleLatency: 21, loadedLatency: 48)
    }

    /// A year of contributions with busy weekdays and quiet weekends.
    public static func github(at now: Date) -> GitHubSummary {
        let calendar = place.calendar
        let today = calendar.startOfDay(for: now)
        let sunday = calendar.date(byAdding: .day, value: -(calendar.component(.weekday, from: today) - 1), to: today)!
        let firstDay = calendar.date(byAdding: .weekOfYear, value: -52, to: sunday)!
        let dayCount = calendar.dateComponents([.day], from: firstDay, to: today).day! + 1
        let contributions = (0..<dayCount).map { day in
            let weekday = day % 7 != 0 && day % 7 != 6
            let wave = 4 * sin(Double(day) * 0.7) + 3 * sin(Double(day) * 0.11) + (weekday ? 4 : -3)
            return max(0, Int(wave.rounded()))
        }
        let weeks = (0..<12).map { week in
            GitHubSummary.Week(start: calendar.date(byAdding: .weekOfYear, value: week - 11, to: sunday)!,
                               added: 600 + Int(900 * abs(sin(Double(week) * 0.9))),
                               deleted: 200 + Int(500 * abs(cos(Double(week) * 0.6))))
        }
        let busiest = max(contributions.max() ?? 0, 1)
        let levels = contributions.map { $0 == 0 ? 0 : min(4, Int((Double($0) / Double(busiest) * 4).rounded(.up))) }
        return GitHubSummary(login: "northlight-dev", contributions: contributions, levels: levels, firstDay: firstDay,
                             openPullRequests: 4, reviewRequests: 2, assignedIssues: 3, weeks: weeks,
                             linesTruncated: false, commits: githubCommits(at: now),
                             repositories: ["northlight-dev/northlight", "northlight-dev/quillify", "northlight-dev/aurora",
                                            "northlight-dev/harbor", "northlight-dev/lantern"])
    }

    /// Five repositories' weekly lines, each begun with an import at a different time.
    public static func codeHistory(at now: Date) -> CodeHistory {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let thisWeek = utc.dateInterval(of: .weekOfYear, for: now)!.start
        let repositories: [(String, Int, Double)] = [
            ("northlight-dev/northlight", 30, 2_400), ("northlight-dev/quillify", 60, 1_500), ("northlight-dev/aurora", 90, 900),
            ("northlight-dev/harbor", 45, 700), ("northlight-dev/lantern", 20, 1_100),
        ]
        return CodeHistory(repositories: repositories.enumerated().map { index, repository in
            let (name, age, pace) = repository
            let weeks = (0..<age).map { week in
                let burst = week == 0 ? 6.0 : 1 + abs(sin(Double(week * (index + 2)) * 0.37))
                return CodeHistory.Week(start: utc.date(byAdding: .weekOfYear, value: week - age + 1, to: thisWeek)!,
                                        added: Int(pace * burst), deleted: Int(pace * 0.45 * abs(cos(Double(week) * 0.5))))
            }
            return CodeHistory.Repository(name: name, weeks: weeks)
        }, skipped: [])
    }

    /// Two reviews asked of the viewer, two of their own pull requests, and a morning's threads.
    public static func githubInbox(at now: Date) -> GitHubInbox {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        let threads: [(String, String?, GitHubInbox.Kind, String, Int?, Double)] = [
            ("quillify", "Bundle Carlito and Liberation fonts", .pullRequest, "review_requested", 285, 14),
            ("harbor", nil, .issue, "mention", 12, 52),
            ("northlight", "CI workflow run failed for main branch", .checkSuite, "ci_activity", nil, 95),
            ("swift-format", "v6.0.0", .release, "subscribed", nil, 260),
            ("aurora", "Where should the briefing go on weekends?", .discussion, "author", 7, 610),
            ("lantern", "Two shifts overlap on a short night", .issue, "assign", 31, 900),
        ]
        return GitHubInbox(
            unread: 9, moreUnread: false,
            notifications: threads.enumerated().map { index, thread in
                GitHubInbox.Notification(id: "\(index)", repository: thread.0, title: thread.1, kind: thread.2, reason: thread.3,
                                         number: thread.4, updatedAt: ago(thread.5))
            },
            reviewRequests: [
                .init(repository: "quillify", number: 285, title: "Bundle Carlito and Liberation fonts", updatedAt: ago(14),
                      isDraft: false, review: .required, checks: .passing),
                .init(repository: "harbor", number: 48, title: nil, updatedAt: ago(180), isDraft: false, review: .required, checks: .pending),
            ],
            reviewRequestCount: 2,
            authored: [
                .init(repository: "northlight", number: 312, title: "Add GitHub inbox and Actions widgets", updatedAt: ago(40),
                      isDraft: false, review: .changesRequested, checks: .failing),
                .init(repository: "aurora", number: 77, title: "Weekly digest on Fridays", updatedAt: ago(320),
                      isDraft: false, review: .approved, checks: .passing),
                .init(repository: "lantern", number: 19, title: "Explain conflicts in the solver", updatedAt: ago(1_500),
                      isDraft: true, review: .none, checks: .pending),
            ],
            authoredCount: 3)
    }

    /// CI running on a branch, a failure on main it may fix, and a few that passed.
    public static func githubActions(at now: Date) -> GitHubActions {
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        let runs: [(String, String, String, GitHubActions.State, Double, Double?)] = [
            ("northlight", "CI", "feature/inbox", .running, 3, nil),
            ("quillify", "Release", "main", .passed, 22, 4.5),
            ("northlight", "CI", "main", .failed, 95, 9),
            ("aurora", "Brief", "main", .passed, 180, 1.2),
            ("harbor", "Tests", "main", .passed, 300, 2.8),
            ("lantern", "CI", "solver-explain", .passed, 1_440, 6.1),
            ("quillify", "CI", "main", .passed, 1_600, 3.3),
        ]
        return GitHubActions(runs: runs.enumerated().map { index, run in
            let created = ago(run.4)
            return GitHubActions.Run(id: index + 1, repository: run.0, workflow: run.1, branch: run.2,
                                     event: run.2 == "main" ? "push" : "pull_request", state: run.3, createdAt: created,
                                     startedAt: created.addingTimeInterval(8),
                                     updatedAt: created.addingTimeInterval(8 + (run.5 ?? 0) * 60))
        }, repositories: ["northlight-dev/northlight", "northlight-dev/quillify", "northlight-dev/aurora",
                          "northlight-dev/harbor", "northlight-dev/lantern"])
    }

    private static func githubCommits(at now: Date) -> [GitHubSummary.Commit] {
        let rows: [(String, String?, TimeInterval, Int, Int)] = [
            ("northlight", "Fix carry lift on rounded tiles", 12 * 60, 48, 31),
            ("quillify", "Bundle Carlito and Liberation fonts", 2 * 3_600, 1_240, 12),
            ("aurora", "Drop stale alerts from the brief", 5 * 3_600, 86, 140),
            ("northlight", "Rank repositories by own commits", 9 * 3_600, 212, 40),
            ("harbor", nil, 26 * 3_600, 310, 95),
            ("northlight", "Cache GitHub per account", 30 * 3_600, 154, 22),
            ("lantern", "Explain conflicts in the solver", 2 * 86_400, 420, 180),
            ("quillify", "Gate invariants for max length", 3 * 86_400, 96, 18),
            ("aurora", "Weekly digest on Fridays", 4 * 86_400, 260, 70),
            ("northlight", "Lighter platters", 5 * 86_400, 64, 58),
            ("harbor", nil, 6 * 86_400, 140, 12),
            ("northlight", "Name what the network tile measures", 8 * 86_400, 188, 75),
        ]
        return rows.enumerated().map { index, row in
            GitHubSummary.Commit(oid: String(format: "%040x", index + 1), repository: row.0, headline: row.1,
                                 date: now.addingTimeInterval(-row.2), additions: row.3, deletions: row.4)
        }
    }

    /// A Claude Code turn editing a file with one subagent, and Codex thinking.
    public static func agents(at now: Date) -> [AgentStatus] {
        [
            AgentStatus(session: "sample-claude", agent: "Claude Code", activity: .tool, verb: "Editing PageCanvas.swift", elapsed: 134,
                        outputTokens: 8_200, project: "northlight", branch: "main",
                        thinking: "The large size has room for a second row of aircraft labels, so the map can keep callsigns readable.",
                        toolName: "Edit", toolTarget: "PageCanvas.swift", subagents: 1, updatedAt: now),
            AgentStatus(session: "sample-codex", agent: "Codex", activity: .thinking, verb: "Thinking", elapsed: 45, outputTokens: 1_900,
                        project: "airmark", branch: "feature/quill", updatedAt: now),
        ]
    }

    public static func usage(at now: Date) -> UsageReading {
        UsageReading(fiveHour: .init(usedPercentage: 42, resetsAt: now.addingTimeInterval(3 * 3_600)),
                     sevenDay: .init(usedPercentage: 18, resetsAt: now.addingTimeInterval(3 * 86_400)),
                     observedAt: now.addingTimeInterval(-90))
    }

    /// Aircraft around the place, with the last five minutes of each one's path.
    public static func flights(at now: Date) -> (flights: [Flight], trails: FlightTrails) {
        let flights = [
            Flight(id: "a1b2c3", label: "ICE451", type: "B39M", altitudeFeet: 11_800, onGround: false, groundSpeedKnots: 310,
                   distanceNM: 9, track: 335, latitude: 64.21, longitude: -22.06),
            Flight(id: "a8f0e1", label: "FDX65", type: "B77L", altitudeFeet: 35_000, onGround: false, groundSpeedKnots: 480,
                   distanceNM: 31, track: 75, latitude: 64.37, longitude: -21.2),
            Flight(id: "c0ffee", label: "ICE688", type: "B38M", altitudeFeet: 6_200, onGround: false, groundSpeedKnots: 240,
                   distanceNM: 18, track: 140, latitude: 63.99, longitude: -22.31),
            Flight(id: "0a0a0a", label: "TF-NLT", type: "C208", altitudeFeet: nil, onGround: true, groundSpeedKnots: 0,
                   distanceNM: 4, track: nil, latitude: 64.13, longitude: -21.94),
        ]
        var trails = FlightTrails()
        for secondsAgo in stride(from: 300.0, through: 0, by: -30) {
            trails.record(flights.map { flight in
                guard let knots = flight.groundSpeedKnots, let track = flight.track,
                      let latitude = flight.latitude, let longitude = flight.longitude else { return flight }
                let then = FlightTrails.Point(latitude: latitude, longitude: longitude, time: now)
                    .flown(knots: knots, track: track + 180, to: now.addingTimeInterval(secondsAgo))
                var earlier = flight
                earlier.latitude = then.latitude
                earlier.longitude = then.longitude
                return earlier
            }, at: now.addingTimeInterval(-secondsAgo))
        }
        return (flights, trails)
    }
}
