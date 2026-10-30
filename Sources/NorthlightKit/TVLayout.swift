import Foundation

/// Which layout a TV holds: `epoch` is drawn once per install, so a revision from
/// before a reinstall never matches, and `n` counts changes since.
public struct LayoutRevision: Codable, Hashable, Sendable {
    public let epoch: UUID
    public let n: Int

    public init(epoch: UUID, n: Int) {
        self.epoch = epoch
        self.n = n
    }

    public var next: LayoutRevision { LayoutRevision(epoch: epoch, n: n + 1) }
}

/// The TV's layout and its revision, kept side by side in UserDefaults.
public struct TVLayout: Equatable, Sendable {
    public private(set) var revision: LayoutRevision
    /// A change made on the TV bumps the revision, so a Mac's edit of the layout before
    /// it no longer applies.
    public var dashboard: Dashboard {
        didSet { if dashboard != oldValue { revision = revision.next } }
    }

    public init(dashboard: Dashboard, revision: LayoutRevision) {
        self.dashboard = dashboard
        self.revision = revision
    }

    /// Takes a Mac's layout when it was built on this revision and the TV is not busy
    /// editing, and returns what to echo to every Mac: the layout the TV now shows,
    /// with the Mac's base when its edit applied.
    public mutating func receive(_ proposal: LayoutFrame, refusing: Bool) -> LayoutFrame {
        guard !refusing, proposal.base == revision else { return frame(base: nil) }
        dashboard = proposal.dashboard
        return frame(base: proposal.base)
    }

    public func frame(base: LayoutRevision? = nil) -> LayoutFrame {
        LayoutFrame(revision: revision, base: base, dashboard: dashboard)
    }

    static let revisionKey = "layoutRevision"

    /// A layout kept without its revision, or none at all, starts a new epoch.
    public static func load(from defaults: UserDefaults) -> TVLayout {
        let dashboard = Dashboard.load(from: defaults)
        if defaults.data(forKey: Dashboard.defaultsKey) != nil,
           let data = defaults.data(forKey: revisionKey),
           let revision = try? JSONDecoder().decode(LayoutRevision.self, from: data) {
            return TVLayout(dashboard: dashboard, revision: revision)
        }
        return TVLayout(dashboard: dashboard, revision: LayoutRevision(epoch: UUID(), n: 0))
    }

    public func save(to defaults: UserDefaults) throws {
        try dashboard.save(to: defaults)
        defaults.set(try JSONEncoder().encode(revision), forKey: Self.revisionKey)
    }
}
