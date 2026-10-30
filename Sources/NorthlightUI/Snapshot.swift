import Foundation
import NorthlightKit

/// Everything the widgets draw from at one instant.
public struct Snapshot {
    public var now: Date
    public var place: Place
    public var weather: Loaded<Weather>
    public var aurora: Loaded<Aurora>
    public var quakes: Loaded<[Quake]>
    /// Nil when no calendar is set.
    public var events: Loaded<[CalendarEvent]>?
    public var airQuality: Loaded<AirQuality>
    public var flights: Loaded<[Flight]>
    public var trails: FlightTrails
    public var flightRadiusNM: Int
    /// Nil until a GitHub account is connected.
    public var github: Loaded<GitHubSummary>?
    /// Lines of code in the viewer's busiest repositories; nil like `github`.
    public var codeHistory: Loaded<CodeHistory>?
    /// Nil like `github`.
    public var githubInbox: Loaded<GitHubInbox>? = nil
    /// Nil like `github`.
    public var githubActions: Loaded<GitHubActions>? = nil
    /// Nil until the Mac is reachable.
    public var agents: [AgentStatus]?
    /// Nil until the first reading.
    public var network: NetworkPath?
    /// Round trips from this Apple TV, 30 s apart.
    public var latency: LatencyHistory
    /// The last speed test, if one has run.
    public var speed: SpeedResult?
    /// The latest briefing the Mac wrote.
    public var briefing: Briefing?
    public var spaceWeather = Loaded<SpaceWeather>(interval: DashboardStore.Cadence.spaceWeather)
    public var xrays = Loaded<[SpaceWeather.XRay]>(interval: DashboardStore.Cadence.xrays)
    public var iss = Loaded<ISSTrack>(interval: DashboardStore.Cadence.iss)
    public var launches = Loaded<[Launch]>(interval: DashboardStore.Cadence.launches)
    public var hackerNews = Loaded<[HNStory]>(interval: DashboardStore.Cadence.hackerNews)
    public var serviceStatus = Loaded<[ServiceStatus]>(interval: DashboardStore.Cadence.serviceStatus)
    public var kev = Loaded<KEVCatalog>(interval: DashboardStore.Cadence.kev)
    public var crypto = Loaded<CryptoMarket>(interval: DashboardStore.Cadence.crypto)
    public var rates = Loaded<ExchangeRates>(interval: DashboardStore.Cadence.rates)
    /// The Claude account's usage, as the Mac last read it.
    public var usage: UsageReading?
}

extension Snapshot {
    @MainActor
    public init(store: DashboardStore, now: Date) {
        self.init(now: now, place: store.config.place, weather: store.weather, aurora: store.aurora,
                  quakes: store.quakes, events: store.agenda(asOf: now),
                  airQuality: store.airQuality, flights: store.flights, trails: store.trails,
                  flightRadiusNM: store.config.flightRadiusNM,
                  github: store.githubFeed(asOf: now), codeHistory: store.codeHistoryFeed(asOf: now),
                  agents: store.agents?.statuses(asOf: now), network: store.path,
                  latency: store.latency, speed: store.speedTests.last, briefing: store.briefing)
        spaceWeather = store.spaceWeather
        xrays = store.xrays
        iss = store.iss
        launches = store.launches
        hackerNews = store.hackerNews
        serviceStatus = store.serviceStatus
        kev = store.kev
        crypto = store.crypto
        rates = store.rates
        usage = store.usage
        githubInbox = store.githubInboxFeed(asOf: now)
        githubActions = store.githubActionsFeed(asOf: now)
    }
}

extension Snapshot {
    /// The readings the TV echoed, for the Mac's mirror. The TV does not echo its
    /// agenda, GitHub or briefing; the agents are this Mac's own.
    public init(status: TVStatus, place: Place, agents: [AgentStatus]?, now: Date) {
        typealias Cadence = DashboardStore.Cadence
        self.init(now: now, place: place, weather: status.weather ?? Loaded(interval: Cadence.weather),
                  aurora: status.aurora ?? Loaded(interval: Cadence.aurora),
                  quakes: status.quakes ?? Loaded(interval: Cadence.quakes), events: nil,
                  airQuality: status.airQuality ?? Loaded(interval: Cadence.airQuality),
                  flights: status.flights ?? Loaded(interval: Cadence.flights), trails: FlightTrails(),
                  flightRadiusNM: status.flightRadiusNM ?? 50, github: nil, codeHistory: nil, agents: agents,
                  network: status.path, latency: status.latency ?? LatencyHistory(), speed: status.speed?.last,
                  briefing: nil)
        status.spaceWeather.map { spaceWeather = $0 }
        status.xrays.map { xrays = $0 }
        status.iss.map { iss = $0 }
        status.launches.map { launches = $0 }
        status.hackerNews.map { hackerNews = $0 }
        status.serviceStatus.map { serviceStatus = $0 }
        status.crypto.map { crypto = $0 }
        status.rates.map { rates = $0 }
    }
}

extension Snapshot {
    /// The sample readings, each fetched a few seconds before `now`, for previews
    /// and the Mac editor.
    public static func sample(at now: Date = Date()) -> Snapshot {
        func ready<T>(_ value: T, every interval: TimeInterval) -> Loaded<T> {
            Loaded(interval: interval, value: value, fetchedAt: now.addingTimeInterval(-12))
        }
        let air = Samples.flights(at: now)
        var sample = Snapshot(now: now, place: Samples.place,
                        weather: ready(Samples.weather(at: now), every: DashboardStore.Cadence.weather),
                        aurora: ready(Samples.aurora(at: now), every: DashboardStore.Cadence.aurora),
                        quakes: ready(Samples.quakes(at: now), every: DashboardStore.Cadence.quakes),
                        events: ready(Samples.events(at: now), every: DashboardStore.Cadence.calendar),
                        airQuality: ready(Samples.airQuality, every: DashboardStore.Cadence.airQuality),
                        flights: ready(air.flights, every: DashboardStore.Cadence.flights), trails: air.trails,
                        flightRadiusNM: 50, github: ready(Samples.github(at: now), every: DashboardStore.Cadence.github),
                        codeHistory: ready(Samples.codeHistory(at: now), every: DashboardStore.Cadence.codeHistory),
                        agents: Samples.agents(at: now), network: Samples.network,
                        latency: Samples.latency(at: now), speed: Samples.speed(at: now),
                        briefing: Samples.briefing(at: now))
        sample.spaceWeather = ready(Samples.spaceWeather(at: now), every: DashboardStore.Cadence.spaceWeather)
        sample.xrays = ready(Samples.xrays(at: now), every: DashboardStore.Cadence.xrays)
        sample.iss = ready(Samples.iss(at: now), every: DashboardStore.Cadence.iss)
        sample.launches = ready(Samples.launches(at: now), every: DashboardStore.Cadence.launches)
        sample.hackerNews = ready(Samples.hackerNews(at: now), every: DashboardStore.Cadence.hackerNews)
        sample.serviceStatus = ready(Samples.serviceStatus, every: DashboardStore.Cadence.serviceStatus)
        sample.kev = ready(Samples.kev(at: now), every: DashboardStore.Cadence.kev)
        sample.crypto = ready(Samples.crypto(at: now), every: DashboardStore.Cadence.crypto)
        sample.rates = ready(Samples.rates, every: DashboardStore.Cadence.rates)
        sample.usage = Samples.usage(at: now)
        sample.githubInbox = ready(Samples.githubInbox(at: now), every: DashboardStore.Cadence.githubInbox)
        sample.githubActions = ready(Samples.githubActions(at: now), every: DashboardStore.Cadence.githubActions)
        return sample
    }
}

extension Snapshot {
    /// What a widget shows as live now. Only a reading the widget would show as
    /// current counts, so a failing feed never glows.
    public func live(for config: WidgetConfig) -> LiveEvent? {
        func ready<T>(_ feed: Loaded<T>?) -> T? {
            if case .ready(let value) = feed?.state(asOf: now) { value } else { nil }
        }
        switch config {
        case .agenda:
            return ready(events).flatMap { LiveEvent.agenda($0, at: now) }
        case .aurora:
            let sun = Solar.elevation(at: now, latitude: place.latitude, longitude: place.longitude)
            return ready(aurora).flatMap { LiveEvent.aurora($0, sunElevation: sun, cloudCover: ready(weather)?.cloudCover) }
        case .seismic:
            return ready(quakes).flatMap { LiveEvent.quakes($0, around: place, at: now) }
        case .flights:
            return ready(flights).flatMap(LiveEvent.flights)
        case .agents:
            return agents.flatMap(LiveEvent.agents)
        case .weather, .forecast, .daylight, .airSnow, .github, .githubLines, .githubCommits, .githubInbox, .githubActions, .network, .briefing:
            return nil
        case .spaceWeather, .iss, .launches, .hackerNews, .serviceStatus, .kev, .markets:
            return nil
        }
    }
}
