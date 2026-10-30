import Foundation

/// A connector's reading as the Mac fetched it, for the TV to show in place of its
/// own feed while it is fresh. Fields added later must be optional, so an older
/// Mac's push still decodes on a newer TV.
public struct Pushed<T: Codable & Sendable & Equatable>: Codable, Sendable, Equatable {
    /// Nil when the Mac has nothing to show yet, as when access is refused.
    public var value: T?
    public var fetchedAt: Date
    public var error: String?
    /// How often the Mac fetches it.
    public var interval: TimeInterval
    /// The Mac's name.
    public var source: String

    public init(value: T?, fetchedAt: Date, error: String? = nil, interval: TimeInterval, source: String) {
        self.value = value
        self.fetchedAt = fetchedAt
        self.error = error
        self.interval = interval
        self.source = source
    }

    /// True within three of the Mac's intervals of its fetch, the same span a feed's
    /// own value outlives failures.
    public func isFresh(asOf now: Date) -> Bool {
        value != nil && now.timeIntervalSince(fetchedAt) <= 3 * interval
    }

    /// The push as a tile reads it. Once the Mac has gone quiet for three intervals
    /// the value reads as unavailable, as a failing feed's would.
    public func loaded(asOf now: Date) -> Loaded<T> {
        let quiet = now.timeIntervalSince(fetchedAt) > 3 * interval ? "Not updated by \(source) lately" : nil
        return Loaded(interval: interval, value: value, fetchedAt: value == nil ? nil : fetchedAt,
                      lastError: error ?? quiet)
    }
}

/// The GitHub account as the Mac fetched it: the summary, the lines of code once
/// they have been counted, the inbox and the Actions runs. An older Mac sends no
/// inbox or runs.
public struct GitHubPush: Codable, Sendable, Equatable {
    public var summary: GitHubSummary
    public var codeHistory: CodeHistory?
    public var inbox: GitHubInbox?
    public var actions: GitHubActions?

    public init(summary: GitHubSummary, codeHistory: CodeHistory?, inbox: GitHubInbox? = nil, actions: GitHubActions? = nil) {
        self.summary = summary
        self.codeHistory = codeHistory
        self.inbox = inbox
        self.actions = actions
    }
}

/// A source the Mac connects for the TV.
public enum Connector: String, Codable, Sendable, CaseIterable {
    case calendar, github
}
