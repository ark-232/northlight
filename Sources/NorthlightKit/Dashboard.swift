import Foundation

/// A widget's footprint on the 4 × 2 grid.
public enum WidgetSize: String, Codable, CaseIterable, Sendable {
    case small, medium, large
    public var cols: Int { self == .small ? 1 : 2 }
    public var rows: Int { self == .large ? 2 : 1 }
    public var cells: Int { cols * rows }
}

/// What a widget shows. Adding a kind or a size bumps `Dashboard.schema`.
public enum WidgetConfig: Codable, Hashable, Sendable {
    case weather, forecast, agenda, flights, aurora, daylight, airSnow, agents, github, network, briefing
    case spaceWeather, iss, launches, hackerNews, serviceStatus, kev, markets
    case githubLines, githubCommits, githubInbox, githubActions
    /// Encodes as {"seismic":{"minMagnitude":2.5}}.
    case seismic(minMagnitude: Double)

    public var sizes: Set<WidgetSize> {
        switch self {
        case .weather, .flights, .agents, .forecast, .agenda, .github, .seismic, .briefing: [.medium, .large]
        case .aurora, .daylight, .airSnow, .network: [.small, .medium]
        case .spaceWeather, .markets: [.small, .medium, .large]
        case .iss, .launches, .hackerNews: [.medium, .large]
        case .serviceStatus: [.small, .medium]
        case .githubActions: [.small, .medium, .large]
        case .kev: [.medium]
        case .githubLines, .githubCommits, .githubInbox: [.medium, .large]
        }
    }

    /// Every kind, in the galleries' order.
    public static let all: [WidgetConfig] = [
        .weather, .forecast, .agenda, .aurora, .daylight, .airSnow,
        .seismic(minMagnitude: 2.5), .flights, .github, .githubLines, .githubCommits, .githubInbox, .githubActions, .agents, .network, .briefing,
        .spaceWeather, .iss, .launches, .hackerNews, .serviceStatus, .kev, .markets,
    ]

    /// What the widget is called outside its own tile.
    public var name: String {
        switch self {
        case .weather: "Weather"
        case .forecast: "Forecast"
        case .agenda: "Agenda"
        case .flights: "Overhead"
        case .aurora: "Aurora"
        case .daylight: "Daylight"
        case .airSnow: "Air & snow"
        case .agents: "Agents"
        case .github: "GitHub"
        case .githubLines: "Lines of code"
        case .githubCommits: "Contributions"
        case .githubInbox: "GitHub inbox"
        case .githubActions: "Actions"
        case .network: "Network"
        case .briefing: "Briefing"
        case .seismic: "Seismic"
        case .spaceWeather: "Space weather"
        case .iss: "ISS"
        case .launches: "Launches"
        case .hackerNews: "Hacker News"
        case .serviceStatus: "Status"
        case .kev: "Known exploited"
        case .markets: "Markets"
        }
    }
}

public struct GridPoint: Hashable, Sendable {
    public var col: Int, row: Int
    public init(col: Int, row: Int) { self.col = col; self.row = row }
}

public struct Placement: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let config: WidgetConfig
    public let size: WidgetSize

    public init?(id: UUID = UUID(), config: WidgetConfig, size: WidgetSize) {
        guard config.sizes.contains(size) else { return nil }
        self.id = id; self.config = config; self.size = size
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let p = Placement(id: try c.decode(UUID.self, forKey: .id),
                                config: try c.decode(WidgetConfig.self, forKey: .config),
                                size: try c.decode(WidgetSize.self, forKey: .size))
        else { throw DecodingError.dataCorruptedError(forKey: .size, in: c, debugDescription: "unsupported size") }
        self = p
    }
}

/// An ordered list of placements that fits in eight cells. Positions are not stored,
/// so overlap, gaps and out-of-bounds placements cannot be represented.
public struct Page: Codable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public var name: String
    public let placements: [Placement]

    public init?(id: UUID = UUID(), name: String, placements: [Placement]) {
        guard PageGrid.fits(placements.map(\.size)) else { return nil }
        self.id = id; self.name = name; self.placements = placements
    }

    public func with(_ placements: [Placement]) -> Page? { Page(id: id, name: name, placements: placements) }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let p = Page(id: try c.decode(UUID.self, forKey: .id),
                           name: try c.decode(String.self, forKey: .name),
                           placements: try c.decode([Placement].self, forKey: .placements))
        else { throw DecodingError.dataCorruptedError(forKey: .placements, in: c, debugDescription: "over 8 cells") }
        self = p
    }
}

public struct Dashboard: Codable, Hashable, Sendable {
    /// Version 2 added the Space, Developer and Markets kinds, version 3 the GitHub
    /// family. Every older layout still decodes, since kinds are only ever added.
    public static let schema = 3, maxPages = 6
    /// The layout's share of the 512 KB that UserDefaults allows before it warns.
    public static let maxBytes = 64 * 1_024
    public let pages: [Page]

    /// Every page holds a widget, so the TV always has one whose menu starts editing.
    public init?(pages: [Page]) {
        guard (1...Self.maxPages).contains(pages.count), pages.allSatisfy({ !$0.placements.isEmpty }) else { return nil }
        self.pages = pages
    }

    public struct NewerSchema: Error { public let version: Int }
    public struct TooLarge: Error { public let bytes: Int }

    private enum CodingKeys: String, CodingKey { case schemaVersion, pages }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let v = try c.decode(Int.self, forKey: .schemaVersion)
        guard v <= Self.schema else { throw NewerSchema(version: v) }
        guard let d = Dashboard(pages: try c.decode([Page].self, forKey: .pages))
        else { throw DecodingError.dataCorruptedError(forKey: .pages, in: c, debugDescription: "page count or an empty page") }
        self = d
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.schema, forKey: .schemaVersion)
        try c.encode(pages, forKey: .pages)
    }

    public init(data: Data) throws {
        guard data.count <= Self.maxBytes else { throw TooLarge(bytes: data.count) }
        self = try JSONDecoder().decode(Dashboard.self, from: data)
    }

    public func data() throws -> Data {
        let data = try JSONEncoder().encode(self)
        guard data.count <= Self.maxBytes else { throw TooLarge(bytes: data.count) }
        return data
    }

    static let defaultsKey = "layout"

    /// The layout kept on this TV. A missing or unreadable one, including one from a
    /// newer version, loads as the default pages.
    public static func load(from defaults: UserDefaults) -> Dashboard {
        guard let data = defaults.data(forKey: defaultsKey), let stored = try? Dashboard(data: data) else { return .defaults }
        return stored
    }

    public func save(to defaults: UserDefaults) throws {
        defaults.set(try data(), forKey: Self.defaultsKey)
    }

    /// A new install's layout, and what "Restore default pages" puts back: five full
    /// pages, the day, the place, the sky, code and the desk.
    public static let defaults = Dashboard(pages: [
        Page(name: "Today", placements: [
            Placement(config: .weather, size: .large)!,
            Placement(config: .agenda, size: .medium)!,
            Placement(config: .briefing, size: .medium)!,
        ])!,
        Page(name: "Outside", placements: [
            Placement(config: .flights, size: .large)!,
            Placement(config: .seismic(minMagnitude: 2.5), size: .medium)!,
            Placement(config: .airSnow, size: .small)!,
            Placement(config: .network, size: .small)!,
        ])!,
        Page(name: "Sky", placements: [
            Placement(config: .spaceWeather, size: .large)!,
            Placement(config: .iss, size: .medium)!,
            Placement(config: .aurora, size: .small)!,
            Placement(config: .daylight, size: .small)!,
        ])!,
        Page(name: "Code", placements: [
            Placement(config: .github, size: .large)!,
            Placement(config: .githubCommits, size: .medium)!,
            Placement(config: .githubActions, size: .medium)!,
        ])!,
        Page(name: "Desk", placements: [
            Placement(config: .agents, size: .large)!,
            Placement(config: .githubInbox, size: .medium)!,
            Placement(config: .hackerNews, size: .medium)!,
        ])!,
    ])!

    /// What restoring the default pages over this layout replaces, for its
    /// confirmation: every widget placed by hand goes with it.
    public var restoringDefaultsMessage: String {
        let widgets = pages.reduce(0) { $0 + $1.placements.count }
        return "This replaces \(pages.map(\.name).formatted(.list(type: .and))), \(widgets) widgets in all, "
            + "with \(Self.defaults.pages.map(\.name).formatted(.list(type: .and)))."
    }

    /// Two pages of widgets that need no account, which the layout tests edit.
    public static let starter = Dashboard(pages: [
        Page(name: "Today", placements: [
            Placement(config: .weather, size: .large)!,
            Placement(config: .agenda, size: .medium)!,
            Placement(config: .aurora, size: .small)!,
            Placement(config: .daylight, size: .small)!,
        ])!,
        Page(name: "Nearby", placements: [
            Placement(config: .flights, size: .large)!,
            Placement(config: .seismic(minMagnitude: 2.5), size: .medium)!,
            Placement(config: .airSnow, size: .small)!,
        ])!,
    ])!
}

/// Packs a page block-major and first-fit: the left 2 × 2 block, then the right
/// one, each span aligned to its own width.
public enum PageGrid {
    public static let cols = 4, rows = 2, capacity = 8

    public static func fits(_ sizes: [WidgetSize]) -> Bool { sizes.reduce(0) { $0 + $1.cells } <= capacity }

    public static func origins(for sizes: [WidgetSize]) -> [GridPoint] {
        precondition(fits(sizes))
        var taken = Set<GridPoint>()
        return sizes.map { size in
            let at = [0, 2].lazy.flatMap { block in
                (0...rows - size.rows).lazy.flatMap { row in
                    stride(from: block, to: block + 2, by: size.cols).lazy.map { GridPoint(col: $0, row: row) }
                }
            }.first { o in cells(o, size).allSatisfy { !taken.contains($0) } }!
            taken.formUnion(cells(at, size))
            return at
        }
    }

    private static func cells(_ o: GridPoint, _ s: WidgetSize) -> [GridPoint] {
        (o.row..<o.row + s.rows).flatMap { r in (o.col..<o.col + s.cols).map { GridPoint(col: $0, row: r) } }
    }
}

public struct Slot: Hashable, Sendable {
    public let index: Int
    public let origin: GridPoint
    public init(index: Int, origin: GridPoint) { self.index = index; self.origin = origin }
}

extension PageGrid {
    /// Places a widget of `size` can take among `others`: one per distinct origin, keeping the
    /// insertion index closest to `current` so dropping where you started changes nothing.
    public static func slots(for size: WidgetSize, among others: [WidgetSize], near current: Int) -> [Slot] {
        guard fits(others + [size]) else { return [] }
        var best: [GridPoint: Int] = [:]
        for i in 0...others.count {
            var order = others
            order.insert(size, at: i)
            let at = origins(for: order)[i]
            if let j = best[at], abs(j - current) <= abs(i - current) { continue }
            best[at] = i
        }
        return best.map { Slot(index: $0.value, origin: $0.key) }.sorted { $0.index < $1.index }
    }
}
