import SwiftUI
import NorthlightKit

/// A page of widgets on the 4 × 2 grid: 410 × 388 pt cells with 40 pt gutters, a
/// 1760 × 816 pt lattice that sits under the header in the tvOS safe area. Each
/// widget goes through `cell`, which the TV uses to make it a button while browsing.
public struct PageCanvas<Cell: View>: View {
    let page: Page
    let snapshot: Snapshot
    let cell: (Placement, WidgetView) -> Cell

    public init(page: Page, snapshot: Snapshot, @ViewBuilder cell: @escaping (Placement, WidgetView) -> Cell) {
        self.page = page
        self.snapshot = snapshot
        self.cell = cell
    }

    public var body: some View {
        let origins = PageGrid.origins(for: page.placements.map(\.size))
        ZStack(alignment: .topLeading) {
            ForEach(Array(page.placements.enumerated()), id: \.element.id) { index, placement in
                cell(placement, WidgetView(placement: placement, snapshot: snapshot))
                    .environment(\.widgetSize, placement.size)
                    .frame(width: Lattice.span(placement.size.cols, Lattice.cell.width),
                           height: Lattice.span(placement.size.rows, Lattice.cell.height))
                    .padding(.leading, CGFloat(origins[index].col) * (Lattice.cell.width + Lattice.gutter))
                    .padding(.top, CGFloat(origins[index].row) * (Lattice.cell.height + Lattice.gutter))
            }
        }
        .frame(width: Lattice.span(PageGrid.cols, Lattice.cell.width), height: Lattice.span(PageGrid.rows, Lattice.cell.height),
               alignment: .topLeading)
    }
}

/// The grid's cells and gutters on screen.
public enum Lattice {
    static let cell = CGSize(width: 410, height: 388)
    static let gutter: CGFloat = 40

    static func span(_ count: Int, _ length: CGFloat) -> CGFloat {
        CGFloat(count) * length + CGFloat(count - 1) * gutter
    }

    /// Where a widget of `size` at `origin` sits on the page.
    public static func frame(at origin: GridPoint, size: WidgetSize) -> CGRect {
        CGRect(x: CGFloat(origin.col) * (cell.width + gutter), y: CGFloat(origin.row) * (cell.height + gutter),
               width: span(size.cols, cell.width), height: span(size.rows, cell.height))
    }
}

/// One widget on its own, at its placement's size: a widget's detail, or a gallery card.
public struct WidgetCard: View {
    let placement: Placement
    let snapshot: Snapshot

    public init(placement: Placement, snapshot: Snapshot) {
        self.placement = placement
        self.snapshot = snapshot
    }

    public var body: some View {
        WidgetView(placement: placement, snapshot: snapshot)
            .environment(\.widgetSize, placement.size)
            .frame(width: Lattice.span(placement.size.cols, Lattice.cell.width),
                   height: Lattice.span(placement.size.rows, Lattice.cell.height))
    }
}

extension EnvironmentValues {
    /// The size of the widget being drawn, so each widget lays out once per size.
    @Entry var widgetSize = WidgetSize.medium
    /// Whether the widget being drawn has a live event, which its tile glows for.
    @Entry var isLive = false
    /// The kind being drawn, which sets its tile's symbol and tint.
    @Entry var widgetKind: WidgetConfig? = nil
}

/// The one place a widget kind becomes a view.
public struct WidgetView: View {
    let placement: Placement
    let snapshot: Snapshot

    public var body: some View {
        kind.environment(\.isLive, snapshot.live(for: placement.config) != nil)
            .environment(\.widgetKind, placement.config)
    }

    @ViewBuilder private var kind: some View {
        let now = snapshot.now
        switch placement.config {
        case .weather:
            WeatherHero(feed: snapshot.weather, place: snapshot.place.name, now: now)
        case .forecast:
            Tile(label: "Forecast", accent: Theme.Palette.cyan, trailing: snapshot.weather.trailing(asOf: now)) {
                FeedBody(state: snapshot.weather.state(asOf: now)) { weather in
                    if placement.size == .large {
                        ForecastList(days: weather.days)
                    } else {
                        ForecastStrip(days: weather.days)
                    }
                }
            }
        case .agenda:
            AgendaTile(feed: snapshot.events, now: now)
        case .aurora:
            AuroraTile(feed: snapshot.aurora, now: now)
        case .daylight:
            DaylightTile(place: snapshot.place, now: now)
        case .airSnow:
            SnowAirTile(weather: snapshot.weather, air: snapshot.airQuality, now: now)
        case .seismic(let floor):
            QuakeTile(feed: snapshot.quakes, minMagnitude: max(floor, snapshot.place.quakeMinMagnitude), now: now)
        case .flights:
            FlightsTile(feed: snapshot.flights, trails: snapshot.trails, place: snapshot.place,
                        radiusNM: snapshot.flightRadiusNM, now: now)
        case .github:
            GitHubTile(feed: snapshot.github, lines: snapshot.codeHistory, now: now)
        case .githubLines:
            GitHubLinesTile(lines: snapshot.codeHistory, now: now)
        case .githubCommits:
            GitHubContributionsTile(feed: snapshot.github, now: now)
        case .githubInbox:
            GitHubInboxTile(feed: snapshot.githubInbox, now: now)
        case .githubActions:
            GitHubActionsTile(feed: snapshot.githubActions, now: now)
        case .agents:
            AgentsTile(statuses: snapshot.agents, usage: snapshot.usage, now: now)
        case .network:
            NetworkTile(path: snapshot.network, latency: snapshot.latency, speed: snapshot.speed, now: now)
        case .briefing:
            BriefingTile(briefing: snapshot.briefing, macReachable: snapshot.agents != nil, now: now)
        case .spaceWeather:
            SpaceWeatherTile(feed: snapshot.spaceWeather, xrays: snapshot.xrays, now: now)
        case .iss:
            ISSTile(feed: snapshot.iss, now: now)
        case .launches:
            LaunchesTile(feed: snapshot.launches, now: now)
        case .hackerNews:
            HackerNewsTile(feed: snapshot.hackerNews, now: now)
        case .serviceStatus:
            ServiceStatusTile(feed: snapshot.serviceStatus, now: now)
        case .kev:
            KEVTile(feed: snapshot.kev, now: now)
        case .markets:
            MarketsTile(crypto: snapshot.crypto, rates: snapshot.rates, now: now)
        }
    }
}
