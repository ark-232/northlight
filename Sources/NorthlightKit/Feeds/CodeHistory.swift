import Foundation

/// Lines of code over time in a few repositories, all authors, from GitHub's weekly
/// code frequency statistics.
public struct CodeHistory: Codable, Sendable, Equatable {
    public var repositories: [Repository]
    /// Repositories GitHub would not count, by owner and name: it refuses any with
    /// 10,000 commits or more.
    public var skipped: [String]

    public struct Repository: Codable, Sendable, Equatable {
        /// Owner and name.
        public var name: String
        /// Oldest first.
        public var weeks: [Week]
    }

    public struct Week: Codable, Sendable, Equatable {
        public var start: Date
        public var added: Int
        public var deleted: Int
    }

    /// What a repository still being computed after three tries reads as.
    public static let counting = "GitHub is counting lines"

    /// Every week any repository reports, oldest first.
    public var weekStarts: [Date] {
        Set(repositories.flatMap { $0.weeks.map(\.start) }).sorted()
    }

    /// The repository's running line count at each of `weekStarts`: none before its
    /// first week, its last count after its last.
    public func lines(of repository: Repository) -> [Int] {
        var weeks = repository.weeks[...], lines = 0
        return weekStarts.map { start in
            while let week = weeks.first, week.start <= start {
                lines += week.added - week.deleted
                weeks = weeks.dropFirst()
            }
            return lines
        }
    }

    /// Every repository's running count added together, at each of `weekStarts`.
    public var totals: [Int] {
        repositories.map(lines(of:)).reduce(into: Array(repeating: 0, count: weekStarts.count)) { totals, lines in
            for index in lines.indices { totals[index] += lines[index] }
        }
    }
}

extension HTTP {
    /// Each repository's weekly lines added and deleted, one after another. GitHub
    /// answers 202 while it computes a repository's statistics, so that one is asked
    /// again after 45 s, three times in all.
    public func codeHistory(token: String, repositories: [String],
                            wait: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) async throws -> CodeHistory {
        var history = CodeHistory(repositories: [], skipped: [])
        for name in repositories {
            var request = URLRequest(url: makeURL("https://api.github.com/repos/\(name)/stats/code_frequency"))
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
            var tries = 0
            asking: while true {
                tries += 1
                let (data, response) = try await session.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                switch status {
                case 202 where tries < 3:
                    try await wait(.seconds(45))
                    continue
                case 202:
                    throw FeedError.refused(CodeHistory.counting)
                case 422:
                    history.skipped.append(name)
                case 204:
                    history.repositories.append(.init(name: name, weeks: []))
                case 200..<300:
                    let rows = data.isEmpty ? [] : try decodeFeed([[Int]].self, from: data)
                    let weeks = rows.compactMap { row in
                        row.count == 3 ? CodeHistory.Week(start: Date(timeIntervalSince1970: TimeInterval(row[0])),
                                                          added: row[1], deleted: -row[2]) : nil
                    }
                    history.repositories.append(.init(name: name, weeks: weeks))
                default:
                    throw FeedError.badStatus(status)
                }
                break asking
            }
        }
        return history
    }
}
