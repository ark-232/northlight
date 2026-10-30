import Foundation

public enum FeedError: Error, Sendable, Equatable {
    case badStatus(Int)
    case decode(String)
    /// The service answered with its own reason for not serving the request.
    case refused(String)
}

/// Thin URLSession wrapper. The User-Agent is mandatory for api.weather.gov and
/// harmless everywhere else, so it goes on every request.
public struct HTTP: Sendable {
    let userAgent: String
    let session: URLSession

    public init(userAgent: String) {
        self.init(userAgent: userAgent, configuration: .ephemeral)
    }

    init(userAgent: String, configuration: URLSessionConfiguration) {
        self.userAgent = userAgent
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.waitsForConnectivity = false
        self.session = URLSession(configuration: configuration)
    }

    func data(_ url: URL, accept: String? = nil) async throws -> Data {
        var request = URLRequest(url: url)
        if let accept { request.setValue(accept, forHTTPHeaderField: "Accept") }
        return try await send(request)
    }

    func send(_ request: URLRequest) async throws -> Data {
        var request = request
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw FeedError.badStatus(http.statusCode)
        }
        return data
    }

    func json<T: Decodable>(_ type: T.Type, from url: URL) async throws -> T {
        try decodeFeed(type, from: try await data(url, accept: "application/json"))
    }

    func text(_ url: URL) async throws -> String {
        let data = try await self.data(url, accept: "text/calendar, text/plain")
        guard let s = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw FeedError.decode("response was not decodable text")
        }
        return s
    }
}

/// Decodes a feed's JSON, reporting a mismatch as the feed's own error.
func decodeFeed<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
    do {
        return try JSONDecoder().decode(type, from: data)
    } catch {
        throw FeedError.decode(String(describing: error))
    }
}

/// Builds a URL from a path and query pairs, failing loudly rather than silently
/// producing a half-formed request.
func makeURL(_ base: String, _ query: [String: String] = [:]) -> URL {
    guard var comps = URLComponents(string: base) else {
        preconditionFailure("malformed base URL in source: \(base)")
    }
    if !query.isEmpty {
        comps.queryItems = query.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
    }
    guard let url = comps.url else {
        preconditionFailure("could not build URL from \(base) with \(query)")
    }
    return url
}
