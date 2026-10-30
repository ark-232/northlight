import Foundation

/// One service's Statuspage summary: its overall indicator and the incident open now.
public struct ServiceStatus: Codable, Sendable, Equatable, Identifiable {
    /// Statuspage's indicator, worst last; `unknown` covers a page that could not be
    /// read and any value Statuspage adds later.
    public enum Indicator: String, Codable, Sendable {
        case none, maintenance, minor, major, critical, unknown
    }

    public var service: String
    public var indicator: Indicator
    public var summary: String
    /// The newest unresolved incident.
    public var incident: String?

    public var id: String { service }

    public init(service: String, indicator: Indicator, summary: String, incident: String?) {
        self.service = service; self.indicator = indicator; self.summary = summary; self.incident = incident
    }
}

public enum ServiceStatusParsing {
    private struct Summary: Decodable {
        struct Status: Decodable { var indicator: String; var description: String }
        struct Incident: Decodable { var name: String }
        var status: Status
        var incidents: [Incident]?
    }

    public static func status(of service: String, from data: Data) throws -> ServiceStatus {
        let summary = try decodeFeed(Summary.self, from: data)
        return ServiceStatus(service: service, indicator: ServiceStatus.Indicator(rawValue: summary.status.indicator) ?? .unknown,
                             summary: summary.status.description, incident: summary.incidents?.first?.name)
    }
}

extension HTTP {
    /// The two Statuspage summaries, keyless. One page failing reads as unknown;
    /// both failing is the feed failing.
    public func serviceStatus() async throws -> [ServiceStatus] {
        func read(_ service: String, _ url: String) async -> Result<ServiceStatus, Error> {
            do { return .success(try ServiceStatusParsing.status(of: service, from: await data(makeURL(url), accept: "application/json"))) }
            catch { return .failure(error) }
        }
        async let github = read("GitHub", "https://www.githubstatus.com/api/v2/summary.json")
        async let claude = read("Claude", "https://status.claude.com/api/v2/summary.json")
        let results = [("GitHub", await github), ("Claude", await claude)]
        if case .failure(let error) = results[0].1, case .failure = results[1].1 { throw error }
        return results.map { service, result in
            (try? result.get()) ?? ServiceStatus(service: service, indicator: .unknown, summary: "Unreachable", incident: nil)
        }
    }
}
