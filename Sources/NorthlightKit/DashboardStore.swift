import CryptoKit
import Foundation
import Network
import Observation

/// One feed's current state. A value outlives a failed refresh on purpose: an
/// unattended wall display should show a slightly old number with its age rather
/// than an empty tile, until three of the feed's intervals have passed since the
/// last success.
public struct Loaded<T: Codable & Sendable>: Sendable {
    /// The feed's refresh interval, which also sets how long a value outlives
    /// failures.
    public let interval: TimeInterval
    public private(set) var value: T?
    public private(set) var fetchedAt: Date?
    public private(set) var lastError: String?

    public init(interval: TimeInterval, value: T? = nil, fetchedAt: Date? = nil, lastError: String? = nil) {
        self.interval = interval
        self.value = value
        self.fetchedAt = fetchedAt
        self.lastError = lastError
    }

    /// What a tile may show. An empty-state sentence belongs to `.ready` alone, so
    /// a dead feed never reads as an empty one.
    public enum State: Sendable {
        case loading
        case ready(T)
        case unavailable(String)
    }

    public func state(asOf now: Date) -> State {
        switch (value, lastError) {
        case (nil, nil):
            return .loading
        case (let value?, nil):
            // Nothing has failed since it arrived; at launch this is the disk seed.
            return .ready(value)
        case (let value?, let error?):
            return (age(asOf: now) ?? .infinity) <= 3 * interval ? .ready(value) : .unavailable(error)
        case (nil, let error?):
            return .unavailable(error)
        }
    }

    public func age(asOf now: Date = Date()) -> TimeInterval? {
        fetchedAt.map { now.timeIntervalSince($0) }
    }

    /// The age once a value has missed two refreshes; nil while it is fresh.
    public func staleAge(asOf now: Date) -> TimeInterval? {
        age(asOf: now).flatMap { $0 > 2 * interval ? $0 : nil }
    }

    mutating func succeed(_ value: T, at date: Date) {
        self.value = value
        fetchedAt = date
        lastError = nil
    }

    mutating func fail(_ reason: String) {
        lastError = reason
    }

    func map<U>(_ transform: (T) -> U) -> Loaded<U> {
        Loaded<U>(interval: interval, value: value.map(transform), fetchedAt: fetchedAt, lastError: lastError)
    }
}

extension Loaded.State: Equatable where T: Equatable {}
extension Loaded: Equatable where T: Equatable {}
extension Loaded: Codable {}

@MainActor
@Observable
public final class DashboardStore {
    public private(set) var weather = Loaded<Weather>(interval: Cadence.weather)
    public private(set) var alerts = Loaded<[WeatherAlert]>(interval: Cadence.alerts)
    public private(set) var aurora = Loaded<Aurora>(interval: Cadence.aurora)
    public private(set) var quakes = Loaded<[Quake]>(interval: Cadence.quakes)
    public private(set) var events = Loaded<[CalendarEvent]>(interval: Cadence.calendar)
    public private(set) var airQuality = Loaded<AirQuality>(interval: Cadence.airQuality)
    public private(set) var flights = Loaded<[Flight]>(interval: Cadence.flights)
    public private(set) var github = Loaded<GitHubSummary>(interval: Cadence.github)
    /// Lines of code in the viewer's busiest repositories, fetched with the summary
    /// at most once a day.
    public private(set) var codeHistory = Loaded<CodeHistory>(interval: Cadence.codeHistory)
    private var codeHistoryTask: Task<Void, Never>?
    /// Reading the cached lines, which a refresh waits for so it sees their age.
    private var codeHistorySeed: Task<Void, Never>?
    /// Unread notifications and the pull requests waiting on the viewer.
    public private(set) var githubInbox = Loaded<GitHubInbox>(interval: Cadence.githubInbox)
    /// The latest Actions runs in the repositories the lines come from.
    public private(set) var githubActions = Loaded<GitHubActions>(interval: Cadence.githubActions)
    public private(set) var spaceWeather = Loaded<SpaceWeather>(interval: Cadence.spaceWeather)
    public private(set) var xrays = Loaded<[SpaceWeather.XRay]>(interval: Cadence.xrays)
    public private(set) var iss = Loaded<ISSTrack>(interval: Cadence.iss)
    public private(set) var launches = Loaded<[Launch]>(interval: Cadence.launches)
    public private(set) var hackerNews = Loaded<[HNStory]>(interval: Cadence.hackerNews)
    public private(set) var serviceStatus = Loaded<[ServiceStatus]>(interval: Cadence.serviceStatus)
    public private(set) var kev = Loaded<KEVCatalog>(interval: Cadence.kev)
    public private(set) var crypto = Loaded<CryptoMarket>(interval: Cadence.crypto)
    public private(set) var rates = Loaded<ExchangeRates>(interval: Cadence.rates)
    /// Where each aircraft has been lately, for the map.
    public private(set) var trails = FlightTrails()
    /// What the paired Mac last said its coding agents were doing.
    public private(set) var agents: AgentReport?
    /// The Claude account's usage, as the Mac last saw it.
    public private(set) var usage: UsageReading?
    /// The TV's connection, while a Network widget watches it.
    public private(set) var path: NetworkPath?
    /// Round trips from the TV, while a Network widget is placed.
    public private(set) var latency = LatencyHistory()
    /// The day's briefing, as the Mac last wrote it.
    public private(set) var briefing: Briefing?
    /// When the TV last asked for one, so a slow Mac is asked at most once a minute.
    private var briefingAsked: Date?
    /// The listener the paired Mac connects to, while it runs.
    private var bridge: BridgeListener?
    /// The agenda the Mac last read from its calendars.
    public private(set) var pushedEvents: Pushed<[CalendarEvent]>?
    /// The GitHub account the Mac last read, redacted there.
    public private(set) var pushedGitHub: Pushed<GitHubPush>?
    /// The Mac's pushes, kept apart from the TV's own feeds so a disconnect forgets
    /// them alone.
    private let macCache: Cache
    /// The last write to `macCache`; each waits for the one before, so a disconnect
    /// cannot be overtaken by the push it forgets.
    private(set) var macCacheWrite: Task<Void, Never>?
    /// Takes the Mac editor's hello, layout and page frames.
    public var onEditorFrame: ((Frame) -> Void)?
    /// Speed tests run on this TV, oldest first.
    public private(set) var speedTests: [SpeedResult] = []
    public private(set) var speedTestRunning = false
    /// Why the last speed test failed, until one succeeds.
    public private(set) var speedTestError: String?
    /// The running or last test's speed as it went, this launch only.
    public private(set) var throughput: [ThroughputPoint] = []
    private var speedTest: Task<Void, Never>?

    /// The feeds with a loop running.
    public var running: Set<Feed> { Set(tasks.keys) }

    public let config: Config
    /// The viewer's units, for what the Mac writes in the briefing. The feeds stay
    /// metric, so a change restarts nothing.
    public var units: Units?
    private let http: HTTP
    private let cache: Cache
    private var tasks: [Feed: Task<Void, Never>] = [:]
    /// Speed tests measure the TV's connection, not a place, so they outlive a move.
    private let speedCache = Cache(name: "Northlight/speed")
    /// One directory per connected account, all deleted when none is connected, since
    /// they hold commit headlines.
    private let githubCaches: Cache

    public convenience init(config: Config) {
        self.init(config: config, http: HTTP(userAgent: config.userAgent))
    }

    init(config: Config, http: HTTP, githubCaches: Cache = Cache(name: "Northlight/github"),
         macCache: Cache = Cache(name: "Northlight/mac")) {
        self.config = config
        self.http = http
        self.githubCaches = githubCaches
        self.macCache = macCache
        if config.githubToken == nil { githubCaches.clear() }
        // One cache directory per place, so a new place never seeds its tiles
        // with the last place's values.
        self.cache = Cache(name: String(format: "Northlight/%.4f,%.4f", config.place.latitude, config.place.longitude))
    }

    /// Refresh cadences. Chosen per source's own update rate, not uniformly:
    /// Open-Meteo recomputes hourly, SWPC every few minutes, NWS on event.
    public enum Cadence {
        public static let weather: TimeInterval = 20 * 60
        public static let alerts: TimeInterval = 5 * 60
        public static let aurora: TimeInterval = 10 * 60
        public static let quakes: TimeInterval = 5 * 60
        public static let calendar: TimeInterval = 10 * 60
        public static let airQuality: TimeInterval = 15 * 60
        /// Often enough to draw each aircraft's path, well inside adsb.fi's
        /// one request a second.
        public static let flights: TimeInterval = 10
        public static let github: TimeInterval = 15 * 60
        public static let codeHistory: TimeInterval = 24 * 3_600
        /// GitHub's notifications ask for at least a minute between reads.
        public static let githubInbox: TimeInterval = 5 * 60
        public static let githubActions: TimeInterval = 5 * 60
        /// The solar wind summaries and the GOES flare file are one-minute products,
        /// under 1 KB of JSON together.
        public static let spaceWeather: TimeInterval = 60
        /// The six-hour X-ray file is about 26 KB compressed, so it is asked for at
        /// most every five minutes, and only for a large widget's chart.
        public static let xrays: TimeInterval = 5 * 60
        /// The station moves about 76 km in ten seconds; wheretheiss.at allows one a second.
        public static let iss: TimeInterval = 10
        /// Launch Library 2 allows 15 requests an hour per address.
        public static let launches: TimeInterval = 15 * 60
        public static let hackerNews: TimeInterval = 5 * 60
        public static let serviceStatus: TimeInterval = 2 * 60
        /// CISA adds to the catalog a few times a week.
        public static let kev: TimeInterval = 60 * 60
        public static let crypto: TimeInterval = 60
        /// The ECB publishes once a working day, around 16:00 CET; a few checks a day
        /// catch it the same day.
        public static let rates: TimeInterval = 6 * 60 * 60
    }

    /// Runs a loop for each of `feeds` and stops the rest.
    public func run(_ feeds: Set<Feed>) {
        for (feed, task) in tasks where !feeds.contains(feed) {
            task.cancel()
            tasks[feed] = nil
        }
        for feed in feeds where tasks[feed] == nil {
            tasks[feed] = loop(for: feed)
        }
    }

    /// How old a feed's value is, or nil before its first. The bridge and the
    /// connection push their values, so they have no age.
    public func age(of feed: Feed, asOf now: Date) -> TimeInterval? {
        switch feed {
        case .weather: weather.age(asOf: now)
        case .alerts: alerts.age(asOf: now)
        case .aurora: aurora.age(asOf: now)
        case .airQuality: airQuality.age(asOf: now)
        case .flights: flights.age(asOf: now)
        case .calendar: events.age(asOf: now)
        case .quakes: quakes.age(asOf: now)
        case .github: github.age(asOf: now)
        case .githubInbox: githubInbox.age(asOf: now)
        case .githubActions: githubActions.age(asOf: now)
        case .spaceWeather: spaceWeather.age(asOf: now)
        case .xrays: xrays.age(asOf: now)
        case .iss: iss.age(asOf: now)
        case .launches: launches.age(asOf: now)
        case .hackerNews: hackerNews.age(asOf: now)
        case .serviceStatus: serviceStatus.age(asOf: now)
        case .kev: kev.age(asOf: now)
        case .crypto: crypto.age(asOf: now)
        case .rates: rates.age(asOf: now)
        case .bridge, .network: nil
        }
    }

    public func staleAge(of feed: Feed, asOf now: Date) -> TimeInterval? {
        switch feed {
        case .weather: weather.staleAge(asOf: now)
        case .alerts: alerts.staleAge(asOf: now)
        case .aurora: aurora.staleAge(asOf: now)
        case .airQuality: airQuality.staleAge(asOf: now)
        case .flights: flights.staleAge(asOf: now)
        case .calendar: events.staleAge(asOf: now)
        case .quakes: quakes.staleAge(asOf: now)
        case .github: github.staleAge(asOf: now)
        case .githubInbox: githubInbox.staleAge(asOf: now)
        case .githubActions: githubActions.staleAge(asOf: now)
        case .spaceWeather: spaceWeather.staleAge(asOf: now)
        case .xrays: xrays.staleAge(asOf: now)
        case .iss: iss.staleAge(asOf: now)
        case .launches: launches.staleAge(asOf: now)
        case .hackerNews: hackerNews.staleAge(asOf: now)
        case .serviceStatus: serviceStatus.staleAge(asOf: now)
        case .kev: kev.staleAge(asOf: now)
        case .crypto: crypto.staleAge(asOf: now)
        case .rates: rates.staleAge(asOf: now)
        case .bridge, .network: nil
        }
    }

    private func recordTrails(_ flights: [Flight]) {
        trails.record(flights, at: Date())
    }

    public func stop() {
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        speedTest?.cancel()
        codeHistoryTask?.cancel()
        codeHistorySeed?.cancel()
    }

    /// Forces every feed to re-fetch now by restarting the loops. A speed test under
    /// way keeps running.
    public func refreshAll() {
        let feeds = Set(tasks.keys)
        tasks.values.forEach { $0.cancel() }
        tasks.removeAll()
        run(feeds)
    }

    private func loop(for feed: Feed) -> Task<Void, Never> {
        let cfg = config
        let place = config.place
        let shared = place.shared
        let client = http
        switch feed {
        case .weather:
            return loop(\.weather, key: "weather") {
                try await client.weather(lat: shared.latitude, lon: shared.longitude, timeZone: place.timeZone)
            }
        case .alerts:
            return loop(\.alerts, key: "alerts") {
                try await client.alerts(lat: shared.latitude, lon: shared.longitude)
            }
        case .aurora:
            return loop(\.aurora, key: "aurora") {
                try await client.aurora(lat: shared.latitude, lon: shared.longitude)
            }
        case .quakes(let minMagnitude):
            return loop(\.quakes, key: "quakes") {
                try await client.quakes(lat: shared.latitude, lon: shared.longitude,
                                        radiusKM: cfg.quakeRadiusKM, minMagnitude: minMagnitude)
            }
        case .calendar(let icsURL, let icloud):
            // Not cached to disk: a cache would outlive the calendar it came from,
            // and a removed or replaced calendar's events would show until a fetch.
            return loop(\.events, key: nil) {
                var sources: [[CalendarEvent]] = []
                if let icsURL {
                    sources.append(try await client.calendar(icsURL: icsURL, calendar: place.calendar))
                }
                if let icloud {
                    sources.append(try await client.icloudEvents(icloud, window: try .agenda(calendar: place.calendar), calendar: place.calendar))
                }
                return CalendarEvent.merged(sources)
            }
        case .airQuality:
            return loop(\.airQuality, key: "airquality") {
                try await client.airQuality(lat: shared.latitude, lon: shared.longitude)
            }
        case .flights:
            // Not cached to disk: the last poll's aircraft are useful, a list
            // restored from the last app launch is misleading.
            return loop(\.flights, key: nil) { [weak self] in
                let flights = try await client.flights(lat: shared.latitude, lon: shared.longitude, radiusNM: cfg.flightRadiusNM)
                await self?.recordTrails(flights)
                return flights
            }
        case .github(let token):
            // Cached under the account's token, so another account never sees it.
            let account = DashboardStore.githubCache(token: token, in: githubCaches)
            codeHistorySeed = Task { [weak self] in
                if let cached = await account.load(CodeHistory.self, as: "lines"), self?.codeHistory.value == nil {
                    self?.codeHistory.succeed(cached.value, at: cached.fetchedAt)
                }
            }
            return loop(\.github, key: "summary", in: account) { [weak self] in
                let summary = try await client.github(token: token, calendar: place.calendar)
                await self?.refreshCodeHistory(after: summary, token: token, cache: account)
                return summary
            }
        case .githubInbox(let token):
            let account = DashboardStore.githubCache(token: token, in: githubCaches), poll = GitHubNotificationPoll()
            return loop(\.githubInbox, key: "inbox", in: account) {
                try await client.githubInbox(token: token, poll: poll)
            }
        case .githubActions(let token):
            let account = DashboardStore.githubCache(token: token, in: githubCaches)
            return loop(\.githubActions, key: "actions", in: account) { [weak self] in
                guard let repositories = try await self?.busiestRepositories() else { throw CancellationError() }
                return try await client.githubActions(token: token, repositories: repositories)
            }
        case .spaceWeather:
            return loop(\.spaceWeather, key: "spaceweather") { try await client.spaceWeather() }
        case .xrays:
            return loop(\.xrays, key: "xrays") { try await client.xrays() }
        case .iss:
            // Not cached to disk, like the aircraft: a track from the last launch has a
            // hole where the TV was off.
            return loop(\.iss, key: nil) { [weak self] in
                let fix = try await client.iss()
                return await self?.iss.value?.adding(fix) ?? ISSTrack(fixes: [fix])
            }
        case .launches:
            return loop(\.launches, key: "launches") { try await client.launches() }
        case .hackerNews:
            return loop(\.hackerNews, key: "hackernews") { try await client.hackerNews() }
        case .serviceStatus:
            return loop(\.serviceStatus, key: "servicestatus") { try await client.serviceStatus() }
        case .kev:
            return loop(\.kev, key: "kev") { try await client.kev() }
        case .crypto:
            return loop(\.crypto, key: "crypto") { try await client.crypto() }
        case .rates:
            return loop(\.rates, key: "rates") { try await client.exchangeRates() }
        case .bridge:
            return listen(key: cfg.bridgeKey!)
        case .network:
            let speedCache = speedCache
            return Task { [weak self] in
                if let stored = await speedCache.load([SpeedResult].self, as: "history"), self?.speedTests.isEmpty == true {
                    self?.speedTests = stored.value
                }
                let probes = Task { [weak self] in
                    while !Task.isCancelled {
                        let gateway = self?.path?.gateway
                        async let internet = LatencyMonitor.probe(host: LatencyMonitor.internetHost, port: 443)
                        let local = if let gateway { await LatencyMonitor.probeGateway(gateway) } else { Double?.none }
                        let answer = await internet
                        guard let self, !Task.isCancelled else { return }
                        let now = Date()
                        latency.record(LatencySample(date: now, milliseconds: answer), to: .internet)
                        if let gateway, gateway == path?.gateway {
                            latency.record(LatencySample(date: now, milliseconds: local), to: .gateway)
                        }
                        try? await Task.sleep(for: LatencyMonitor.interval)
                    }
                }
                await withTaskCancellationHandler {
                    for await update in NWPathMonitor() {
                        let path = NetworkPath(update)
                        if path.gateway != self?.path?.gateway { self?.latency.clearGateway() }
                        self?.path = path
                    }
                } onCancel: {
                    probes.cancel()
                }
            }
        }
    }

    /// Fetches lines of code once a day, or sooner after a failure, beside the summary
    /// rather than in its way. The repositories are the viewer's five busiest, kept
    /// for a day, so the total moves only when code does.
    private func refreshCodeHistory(after summary: GitHubSummary, token: String, cache: Cache) async {
        await codeHistorySeed?.value
        let age = codeHistory.age() ?? .infinity
        guard codeHistoryTask == nil, age >= Cadence.codeHistory || codeHistory.lastError != nil else { return }
        let kept = codeHistory.value.map { $0.repositories.map(\.name) + $0.skipped }
        let repositories = (age < Cadence.codeHistory ? kept : nil) ?? Array(summary.repositories.prefix(5))
        let client = http
        codeHistoryTask = Task { [weak self] in
            do {
                let history = try await client.codeHistory(token: token, repositories: repositories)
                self?.codeHistory.succeed(history, at: Date())
                await cache.save(history, as: "lines")
            } catch where !Task.isCancelled {
                self?.codeHistory.fail(DashboardStore.describe(error))
            } catch {}
            self?.codeHistoryTask = nil
        }
    }

    /// The five repositories the lines come from, once the summary has named them.
    private func busiestRepositories() async throws -> [String] {
        while github.value == nil {
            try await Task.sleep(for: .milliseconds(250))
        }
        return Array(github.value!.repositories.prefix(5))
    }

    /// Takes the paired Mac's reports and briefings for as long as the bridge feed runs,
    /// starting the listener again if the network takes it down. Each report is the
    /// Mac saying it is there, so a briefing due is asked for then.
    private func listen(key: SymmetricKey) -> Task<Void, Never> {
        let cache = cache
        return Task { [weak self] in
            if let stored = await cache.load(Briefing.self, as: "briefing"), self?.briefing == nil {
                self?.briefing = stored.value
            }
            await self?.seedPushed()
            while !Task.isCancelled {
                if let listener = try? BridgeListener(key: key, service: NWListener.Service(type: Bridge.serviceType)) {
                    defer { listener.cancel() }
                    if (try? await listener.start()) != nil {
                        self?.bridge = listener
                        for await frame in listener.frames {
                            guard let self else { return }
                            switch frame {
                            case .agents(let statuses):
                                agents = AgentReport(statuses: statuses, receivedAt: Date())
                                let now = Date()
                                if Briefing.isDue(after: briefing?.at, at: now, calendar: config.place.calendar),
                                   briefingAsked.map({ now.timeIntervalSince($0) >= 60 }) ?? true {
                                    askForBriefing(at: now)
                                }
                            case .briefing(let written):
                                briefing = written
                                Task { await cache.save(written, as: "briefing") }
                            case .events, .github, .disconnected:
                                receive(frame)
                            case .hello, .layout, .showPage:
                                onEditorFrame?(frame)
                            case .briefingRequest, .tvStatus:
                                break
                            case .usage(let reading):
                                usage = reading
                            }
                        }
                        self?.bridge = nil
                    }
                }
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    /// Takes what a Mac's connectors push.
    public func receive(_ frame: Frame) {
        switch frame {
        case .events(let pushed):
            pushedEvents = pushed
            writeMacCache { await $0.save(pushed, as: "events") }
        case .github(let pushed):
            pushedGitHub = pushed
            writeMacCache { await $0.save(pushed, as: "github") }
        case .disconnected(.calendar):
            pushedEvents = nil
            writeMacCache { await $0.remove("events") }
        case .disconnected(.github):
            pushedGitHub = nil
            writeMacCache { await $0.remove("github") }
        case .agents, .briefingRequest, .briefing, .usage, .hello, .layout, .tvStatus, .showPage:
            break
        }
    }

    private func writeMacCache(_ write: @escaping @Sendable (Cache) async -> Void) {
        let previous = macCacheWrite, cache = macCache
        macCacheWrite = Task {
            await previous?.value
            await write(cache)
        }
    }

    /// The Mac's last pushes from before this launch, unless one has arrived since.
    func seedPushed() async {
        await macCacheWrite?.value
        if pushedEvents == nil, let stored = await macCache.load(Pushed<[CalendarEvent]>.self, as: "events") {
            pushedEvents = stored.value
        }
        if pushedGitHub == nil, let stored = await macCache.load(Pushed<GitHubPush>.self, as: "github") {
            pushedGitHub = stored.value
        }
    }

    /// The agenda to show: the Mac's while it is fresh, else this TV's own, else the
    /// Mac's aging out. Nil when neither has a calendar.
    public func agenda(asOf now: Date) -> Loaded<[CalendarEvent]>? {
        if let pushedEvents, pushedEvents.isFresh(asOf: now) { return pushedEvents.loaded(asOf: now) }
        if config.hasCalendar { return events }
        return pushedEvents?.loaded(asOf: now)
    }

    /// The GitHub summary to show, chosen as `agenda(asOf:)` chooses.
    public func githubFeed(asOf now: Date) -> Loaded<GitHubSummary>? {
        if let pushed = pushedGitHub, pushed.isFresh(asOf: now) || config.githubToken == nil {
            return pushed.loaded(asOf: now).map(\.summary)
        }
        return config.githubToken == nil ? nil : github
    }

    /// The lines of code beside whichever summary `githubFeed(asOf:)` chose.
    public func codeHistoryFeed(asOf now: Date) -> Loaded<CodeHistory>? {
        if let pushed = pushedGitHub, pushed.isFresh(asOf: now) || config.githubToken == nil {
            return Loaded(interval: Cadence.codeHistory, value: pushed.value?.codeHistory,
                          fetchedAt: pushed.value?.codeHistory == nil ? nil : pushed.fetchedAt)
        }
        return config.githubToken == nil ? nil : codeHistory
    }

    /// The inbox beside whichever summary `githubFeed(asOf:)` chose.
    public func githubInboxFeed(asOf now: Date) -> Loaded<GitHubInbox>? {
        if let pushed = pushedGitHub, pushed.isFresh(asOf: now) || config.githubToken == nil {
            return Loaded(interval: Cadence.githubInbox, value: pushed.value?.inbox,
                          fetchedAt: pushed.value?.inbox == nil ? nil : pushed.fetchedAt)
        }
        return config.githubToken == nil ? nil : githubInbox
    }

    /// The Actions runs beside whichever summary `githubFeed(asOf:)` chose.
    public func githubActionsFeed(asOf now: Date) -> Loaded<GitHubActions>? {
        if let pushed = pushedGitHub, pushed.isFresh(asOf: now) || config.githubToken == nil {
            return Loaded(interval: Cadence.githubActions, value: pushed.value?.actions,
                          fetchedAt: pushed.value?.actions == nil ? nil : pushed.fetchedAt)
        }
        return config.githubToken == nil ? nil : githubActions
    }

    /// Sends to every Mac on the bridge; with none there, nothing goes.
    public func sendToMacs(_ frame: Frame) {
        try? bridge?.send(frame)
    }

    /// Asks the Mac on the bridge, if one is, to write the day's briefing now.
    /// Presses within five seconds of the last ask ask nothing more.
    public func writeBriefingNow() {
        let now = Date()
        guard briefingAsked.map({ now.timeIntervalSince($0) >= 5 }) ?? true else { return }
        askForBriefing(at: now)
    }

    private func askForBriefing(at now: Date) {
        guard let bridge else { return }
        briefingAsked = now
        let request = BriefingRequest(place: config.place, at: now, locale: Locale.current.identifier, units: units,
                                      weather: weather.value, events: agenda(asOf: now)?.value ?? [], alerts: alerts.value ?? [])
        do {
            try bridge.send(.briefingRequest(request))
        } catch {
            briefing = .unavailable(reason: "The TV could not ask: \(DashboardStore.describe(error)).", at: now)
        }
    }

    /// One independent loop per feed. A failure here backs that feed off without
    /// touching any other, which is the whole point of not sharing a timer.
    private func loop<T: Codable & Sendable>(
        _ keyPath: ReferenceWritableKeyPath<DashboardStore, Loaded<T>>,
        key: String?,
        in cache: Cache? = nil,
        fetch: @escaping @Sendable () async throws -> T
    ) -> Task<Void, Never> {
        let interval = self[keyPath: keyPath].interval
        let cache = cache ?? self.cache

        return Task { [weak self] in
            // Seed from the on-disk last-good value so the tile is not empty while
            // the first fetch is in flight.
            if let key, let cached = await cache.load(T.self, as: key) {
                guard let self else { return }
                if self[keyPath: keyPath].value == nil {
                    self[keyPath: keyPath].succeed(cached.value, at: cached.fetchedAt)
                }
            }

            var failures = 0
            while !Task.isCancelled {
                do {
                    let value = try await fetch()
                    guard let self, !Task.isCancelled else { return }
                    self[keyPath: keyPath].succeed(value, at: Date())
                    if let key { await cache.save(value, as: key) }
                    failures = 0
                } catch is CancellationError {
                    return
                } catch {
                    guard let self, !Task.isCancelled else { return }
                    failures += 1
                    self[keyPath: keyPath].fail(DashboardStore.describe(error))
                }

                try? await Task.sleep(for: .seconds(DashboardStore.delay(afterFailures: failures, interval: interval)))
            }
        }
    }

    /// The wait before the next attempt. A failing feed retries from 30 s and backs
    /// off exponentially to the longer of its interval and fifteen minutes, so a
    /// blip at launch clears quickly and a dead endpoint is not hammered.
    nonisolated static func delay(afterFailures failures: Int, interval: TimeInterval) -> TimeInterval {
        guard failures > 0 else { return interval }
        return min(15 * pow(2, Double(failures)), max(interval, 900))
    }

    /// Runs one speed test against the nearest M-Lab server, unless one is running. M-Lab
    /// publishes the TV's public IP address with the result, so the viewer has agreed.
    public func runSpeedTest() {
        guard !speedTestRunning else { return }
        if let refusal = path?.speedTestRefusal {
            speedTestError = refusal
            return
        }
        speedTestRunning = true
        throughput = []
        let client = http, speedCache = speedCache
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let (points, publish) = AsyncStream<ThroughputPoint>.makeStream()
        let drawing = Task { [weak self] in
            for await point in points { self?.throughput.append(point) }
        }
        speedTest = Task { [weak self] in
            defer { publish.finish() }
            do {
                let result = try await client.speedTest(on: client.nearestNDT7Server(clientVersion: version)) { publish.yield($0) }
                publish.finish()
                await drawing.value
                guard let self else { return }
                speedTests = Array((speedTests + [result]).suffix(30))
                speedTestError = nil
                await speedCache.save(speedTests, as: "history")
            } catch where !Task.isCancelled {
                self?.speedTestError = DashboardStore.describe(error)
            } catch {}
            self?.speedTestRunning = false
        }
    }

    /// The directory for the account `token` signs in, named by a digest so the token
    /// never reaches the disk.
    static func githubCache(token: String, in caches: Cache) -> Cache {
        let digest = SHA256.hash(data: Data(token.utf8)).prefix(8).map { String(format: "%02x", $0) }.joined()
        return Cache(directory: caches.directory.appendingPathComponent(digest, isDirectory: true))
    }

    public static func describe(_ error: Error) -> String {
        switch error {
        case FeedError.badStatus(let code): return "HTTP \(code)"
        case FeedError.decode: return "Unreadable response"
        case FeedError.refused(let reason): return reason
        default:
            let ns = error as NSError
            return ns.localizedDescription
        }
    }
}

/// A source the store polls. A feed's payload is part of its identity, so a new
/// calendar or quake threshold restarts that loop.
public enum Feed: Hashable, Sendable {
    case weather, alerts, aurora, airQuality, flights
    case calendar(ics: URL?, icloud: ICloudAccount?)
    case quakes(minMagnitude: Double)
    case github(token: String)
    case githubInbox(token: String)
    case githubActions(token: String)
    case spaceWeather, xrays, iss, launches, hackerNews, serviceStatus, kev, crypto, rates
    /// The paired Mac's channel, for agent status, the briefing and the editor.
    case bridge
    case network

    /// The feeds a dashboard's widgets read at `config`'s place. Alerts run wherever
    /// NWS issues them, because they tint the header on every page.
    public static func needed(by dashboard: Dashboard, config: Config) -> Set<Feed> {
        var feeds: Set<Feed> = config.place.hasNWSAlerts ? [.alerts] : []
        // The Mac's editor reaches the TV over the bridge, whatever the layout holds.
        if config.bridgeKey != nil { feeds.insert(.bridge) }
        var seismicFloors: [Double] = []
        for placement in dashboard.pages.flatMap(\.placements) {
            switch placement.config {
            case .weather, .forecast: feeds.insert(.weather)
            case .agenda:
                if config.bridgeKey != nil { feeds.insert(.bridge) }
                if config.hasCalendar {
                    feeds.insert(.calendar(ics: config.calendarICSURL, icloud: config.icloud?.calendars.isEmpty == false ? config.icloud : nil))
                }
            case .flights: feeds.insert(.flights)
            case .aurora: feeds.formUnion([.aurora, .weather])
            case .airSnow: feeds.formUnion([.airQuality, .weather])
            case .seismic(let minMagnitude): seismicFloors.append(minMagnitude)
            case .github, .githubLines, .githubCommits: if let token = config.githubToken { feeds.insert(.github(token: token)) }
            case .githubInbox: if let token = config.githubToken { feeds.insert(.githubInbox(token: token)) }
            case .githubActions:
                if let token = config.githubToken { feeds.formUnion([.github(token: token), .githubActions(token: token)]) }
            case .agents, .briefing: break
            case .network: feeds.insert(.network)
            case .daylight: break
            case .spaceWeather:
                feeds.insert(.spaceWeather)
                if placement.size == .large { feeds.insert(.xrays) }
            case .iss: feeds.insert(.iss)
            case .launches: feeds.insert(.launches)
            case .hackerNews: feeds.insert(.hackerNews)
            case .serviceStatus: feeds.insert(.serviceStatus)
            case .kev: feeds.insert(.kev)
            case .markets: feeds.formUnion([.crypto, .rates])
            }
        }
        // One fetch serves every seismic widget, from the lowest floor any of them
        // asks for, but never below what USGS catalogs at the place.
        if let lowest = seismicFloors.min() {
            feeds.insert(.quakes(minMagnitude: max(lowest, config.place.quakeMinMagnitude)))
        }
        return feeds
    }
}
