import Foundation

/// A vulnerability CISA has seen exploited in the wild.
public struct KEVEntry: Codable, Sendable, Equatable, Identifiable {
    public var cve: String
    public var vendor: String
    public var product: String
    /// The day CISA added it, at midnight UTC.
    public var added: Date

    public var id: String { cve }

    public init(cve: String, vendor: String, product: String, added: Date) {
        self.cve = cve; self.vendor = vendor; self.product = product; self.added = added
    }
}

/// The catalog's size and its last month of additions, newest first. The full
/// catalog is nearly 2 MB, so only this much is kept.
public struct KEVCatalog: Codable, Sendable, Equatable {
    public var count: Int
    public var recent: [KEVEntry]

    public init(count: Int, recent: [KEVEntry]) { self.count = count; self.recent = recent }

    /// Entries added in the seven UTC days ending today.
    public func addedThisWeek(at now: Date) -> Int {
        let start = KEVParsing.utc.date(byAdding: .day, value: -6, to: KEVParsing.utc.startOfDay(for: now))!
        return recent.count { $0.added >= start }
    }
}

public enum KEVParsing {
    private struct Payload: Decodable {
        struct Row: Decodable {
            var cveID: String
            var vendorProject: String
            var product: String
            var dateAdded: String
        }
        var count: Int
        var vulnerabilities: [Row]
    }

    static let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    public static func catalog(from data: Data, now: Date) throws -> KEVCatalog {
        let payload = try decodeFeed(Payload.self, from: data)
        let since = utc.date(byAdding: .day, value: -30, to: utc.startOfDay(for: now))!
        let recent = payload.vulnerabilities.enumerated().compactMap { index, row -> (Int, KEVEntry)? in
            guard let added = try? Date(row.dateAdded + "T00:00:00Z", strategy: .iso8601), added >= since else { return nil }
            return (index, KEVEntry(cve: row.cveID, vendor: row.vendorProject, product: row.product, added: added))
        }
        // Newest day first, keeping the catalog's own order within a day.
        .sorted { $0.1.added != $1.1.added ? $0.1.added > $1.1.added : $0.0 < $1.0 }
        .map(\.1)
        return KEVCatalog(count: payload.count, recent: recent)
    }
}

extension HTTP {
    /// CISA's KEV catalog, keyless and CC0.
    public func kev(now: Date = Date()) async throws -> KEVCatalog {
        try KEVParsing.catalog(from: await data(makeURL("https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json"),
                                                accept: "application/json"),
                               now: now)
    }
}
