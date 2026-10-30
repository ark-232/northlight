import Foundation

/// The signed-in account's GitHub at a glance.
public struct GitHubSummary: Codable, Sendable, Equatable {
    public var login: String
    /// Contributions per day over the last year, oldest first, from a Sunday as on
    /// the profile's calendar.
    public var contributions: [Int]
    /// GitHub's shade for each day of `contributions`, 0 for none to 4 for its busiest quarter.
    public var levels: [Int]
    public var firstDay: Date
    public var openPullRequests: Int
    public var reviewRequests: Int
    public var assignedIssues: Int
    /// Lines added and deleted by week, oldest first.
    public var weeks: [Week]
    /// True when a repository had more commits in the window than were fetched, so
    /// its oldest weeks are partly counted.
    public var linesTruncated: Bool
    /// The viewer's newest commits on default branches in the window, newest first,
    /// merges left out.
    public var commits: [Commit]
    /// Repositories by owner and name, the ones the viewer committed to most in the
    /// window first.
    public var repositories: [String]

    public struct Week: Codable, Sendable, Equatable {
        public var start: Date
        public var added: Int
        public var deleted: Int
    }

    public struct Commit: Codable, Sendable, Equatable {
        public var oid: String
        /// The repository's name without its owner.
        public var repository: String
        /// Nil for a private repository, whose messages stay off the TV.
        public var headline: String?
        public var date: Date
        public var additions: Int
        public var deletions: Int
    }

    public var totalContributions: Int { contributions.reduce(0, +) }

    public struct WeekCount: Sendable, Equatable {
        public var start: Date
        public var count: Int
    }

    /// Contributions in each of the calendar's latest 52 weeks, oldest first, this
    /// week so far last. Each starts on the calendar's Sunday in `calendar`'s zone.
    public func contributionWeeks(calendar: Calendar) -> [WeekCount] {
        stride(from: 0, to: contributions.count, by: 7).map { first in
            WeekCount(start: calendar.date(byAdding: .day, value: first, to: firstDay)!,
                      count: contributions[first..<min(first + 7, contributions.count)].reduce(0, +))
        }.suffix(52).map { $0 }
    }

    /// Each value's mean with the ones before it, up to `window` in all.
    public static func trailingAverage(_ values: [Int], over window: Int) -> [Double] {
        values.indices.map { index in
            let slice = values[max(0, index - window + 1)...index]
            return Double(slice.reduce(0, +)) / Double(slice.count)
        }
    }
}

/// GitHub's device flow: the app shows a code, the owner types it at
/// github.com/login/device, and the app polls until it is approved.
public enum GitHubDeviceFlow {
    /// The Northlight OAuth App's. Device flow has no client secret, so this is public.
    public static let clientID = "Ov23lid13Rowxj3vRr7p"

    /// Asks for a code, hands it to `onCode` to show, then polls until GitHub
    /// approves it and returns the token, or throws GitHub's reason for refusing. A
    /// poll lost to the network is retried; the code's expiry ends the wait.
    public static func signIn(http: HTTP, clientID: String = clientID,
                              onCode: @Sendable (Code) async -> Void,
                              wait: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }) async throws -> String {
        let code = try await http.githubDeviceCode(clientID: clientID)
        await onCode(code)
        var interval = code.interval
        while true {
            try await wait(.seconds(interval))
            try Task.checkCancellation()
            guard let poll = try? await http.githubToken(clientID: clientID, code: code, interval: interval) else { continue }
            switch poll {
            case .wait(let seconds): interval = seconds
            case .token(let token): return token
            case .failed(let reason): throw FeedError.refused(reason)
            }
        }
    }

    public struct Code: Decodable, Sendable, Equatable {
        public let deviceCode: String
        public let userCode: String
        public let verificationURI: URL
        public let expiresIn: Int
        public let interval: Int

        enum CodingKeys: String, CodingKey {
            case deviceCode = "device_code", userCode = "user_code", verificationURI = "verification_uri"
            case expiresIn = "expires_in", interval
        }
    }

    public enum Poll: Equatable, Sendable {
        case token(String)
        case wait(seconds: Int)
        case failed(String)
    }

    /// The code to show, or GitHub's reason for giving none.
    public static func code(from data: Data) throws -> Code {
        struct Refusal: Decodable { var error: String; var error_description: String? }
        if let refusal = try? JSONDecoder().decode(Refusal.self, from: data) {
            throw FeedError.refused(refusal.error_description ?? refusal.error)
        }
        return try decodeFeed(Code.self, from: data)
    }

    /// What to do after one poll of the token endpoint, which answers in the body
    /// whether or not the code has been approved.
    public static func poll(from data: Data, interval: Int) throws -> Poll {
        struct Answer: Decodable {
            var access_token: String?
            var error: String?
            var error_description: String?
            var interval: Int?
        }
        let answer = try decodeFeed(Answer.self, from: data)
        if let token = answer.access_token { return .token(token) }
        switch answer.error {
        case "authorization_pending": return .wait(seconds: interval)
        case "slow_down": return .wait(seconds: answer.interval ?? interval + 5)
        case "access_denied": return .failed("Sign-in was cancelled on GitHub.")
        case "expired_token": return .failed("The code expired. Start again.")
        default: return .failed(answer.error_description ?? answer.error ?? "GitHub gave no answer.")
        }
    }
}

enum GitHubParsing {
    static let summaryQuery = """
    query {
      viewer {
        id
        login
        contributionsCollection { contributionCalendar { weeks { contributionDays { date contributionCount contributionLevel } } } }
      }
      pullRequests: search(query: "is:pr is:open author:@me archived:false", type: ISSUE) { issueCount }
      reviewRequests: search(query: "is:pr is:open review-requested:@me archived:false", type: ISSUE) { issueCount }
      assignedIssues: search(query: "is:issue is:open assignee:@me archived:false", type: ISSUE) { issueCount }
    }
    """

    private static let page = """
    history(first: 100, after: $after, since: $since, author: {id: $author}) {
      pageInfo { hasNextPage endCursor }
      nodes { oid messageHeadline committedDate additions deletions parents { totalCount } }
    }
    """

    static let historyQuery = """
    query($author: ID!, $since: GitTimestamp!, $after: String) {
      viewer {
        repositories(first: 20, orderBy: {field: PUSHED_AT, direction: DESC},
                     ownerAffiliations: [OWNER, COLLABORATOR, ORGANIZATION_MEMBER], isFork: false) {
          nodes { id name nameWithOwner isPrivate defaultBranchRef { target { ... on Commit { \(page) } } } }
        }
      }
    }
    """

    static let pageQuery = """
    query($repository: ID!, $author: ID!, $since: GitTimestamp!, $after: String) {
      node(id: $repository) {
        ... on Repository { id name nameWithOwner isPrivate defaultBranchRef { target { ... on Commit { \(page) } } } }
      }
    }
    """

    struct Commit: Decodable {
        struct Parents: Decodable { var totalCount: Int }
        var oid: String
        var messageHeadline: String
        var committedDate: String
        var additions: Int
        var deletions: Int
        var parents: Parents
        /// The repository it was read from, set after decoding.
        var source = Source(name: "", nameWithOwner: "", isPrivate: true)

        enum CodingKeys: String, CodingKey { case oid, messageHeadline, committedDate, additions, deletions, parents }
    }

    struct Source { var name: String; var nameWithOwner: String; var isPrivate: Bool }

    /// One page of a repository's default-branch history, and the cursor to the next.
    struct History {
        var repository: String
        var commits: [Commit]
        var next: String?
    }

    private struct Repository: Decodable {
        struct Branch: Decodable { var target: Target? }
        struct Target: Decodable { var history: Page? }
        struct Page: Decodable {
            struct Info: Decodable { var hasNextPage: Bool; var endCursor: String? }
            var pageInfo: Info
            var nodes: [Commit?]
        }
        var id: String
        var name: String
        var nameWithOwner: String
        var isPrivate: Bool
        var defaultBranchRef: Branch?

        var history: History? {
            let source = Source(name: name, nameWithOwner: nameWithOwner, isPrivate: isPrivate)
            return defaultBranchRef?.target?.history.map { page in
                History(repository: id, commits: page.nodes.compactMap { $0 }.map { var commit = $0; commit.source = source; return commit },
                        next: page.pageInfo.hasNextPage ? page.pageInfo.endCursor : nil)
            }
        }
    }

    private struct SummaryPayload: Decodable {
        struct Fields: Decodable {
            struct Viewer: Decodable {
                struct Collection: Decodable { var contributionCalendar: Contributions }
                struct Contributions: Decodable { var weeks: [Week] }
                struct Week: Decodable { var contributionDays: [Day] }
                struct Day: Decodable { var date: String; var contributionCount: Int; var contributionLevel: String }
                var id: String
                var login: String
                var contributionsCollection: Collection
            }
            struct Count: Decodable { var issueCount: Int }
            var viewer: Viewer
            var pullRequests: Count
            var reviewRequests: Count
            var assignedIssues: Count
        }
        var data: Fields
    }

    private struct Errors: Decodable {
        struct Item: Decodable { var message: String }
        var errors: [Item]
    }

    /// A GraphQL answer's data, or its first error when the data is unusable, as when
    /// the rate limit runs out.
    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try decodeFeed(type, from: data)
        } catch {
            guard let first = (try? JSONDecoder().decode(Errors.self, from: data))?.errors.first else { throw error }
            throw FeedError.refused(first.message)
        }
    }

    /// The first page of each repository's history.
    static func histories(from data: Data) throws -> [History] {
        struct Answer: Decodable {
            struct Fields: Decodable { var viewer: Viewer }
            struct Viewer: Decodable { var repositories: Repositories }
            struct Repositories: Decodable { var nodes: [Repository?] }
            var data: Fields
        }
        return try decode(Answer.self, from: data).data.viewer.repositories.nodes.compactMap { $0?.history }
    }

    /// A later page of one repository's history.
    static func history(from data: Data) throws -> History {
        struct Answer: Decodable { struct Fields: Decodable { var node: Repository }; var data: Fields }
        guard let history = try decode(Answer.self, from: data).data.node.history else {
            throw FeedError.decode("no history on a later page")
        }
        return history
    }

    /// Every commit in `first` and the pages after it, reading at most `extraPages`
    /// more in all. Truncated when a history still had pages left.
    static func readAll(_ first: [History], extraPages: Int,
                        next: (History) async throws -> History) async throws -> (commits: [Commit], truncated: Bool) {
        var commits: [Commit] = [], budget = extraPages
        for var history in first {
            commits += history.commits
            while history.next != nil {
                guard budget > 0 else { return (commits, true) }
                budget -= 1
                history = try await next(history)
                commits += history.commits
            }
        }
        return (commits, false)
    }

    /// The starts of the twelve weeks the chart shows, oldest first. Each is found
    /// from within its own week: stepping from a start that a clock change moved off
    /// midnight would carry the shift into every other week.
    static func weekStarts(calendar: Calendar, now: Date) -> [Date] {
        (-11...0).map { calendar.dateInterval(of: .weekOfYear, for: calendar.date(byAdding: .weekOfYear, value: $0, to: now)!)!.start }
    }

    static func summary(from data: Data, commits: [Commit], truncated: Bool, calendar: Calendar, now: Date,
                        keepsPrivateHeadlines: Bool = false) throws -> GitHubSummary {
        let summary = try decode(SummaryPayload.self, from: data).data
        let days = summary.viewer.contributionsCollection.contributionCalendar.weeks.flatMap(\.contributionDays)
        let dayFormat = DateFormatter()
        dayFormat.locale = Locale(identifier: "en_US_POSIX")
        dayFormat.dateFormat = "yyyy-MM-dd"
        dayFormat.timeZone = calendar.timeZone
        guard let first = days.first, let firstDay = dayFormat.date(from: first.date) else {
            throw FeedError.decode("empty contribution calendar")
        }

        // A merge repeats lines its branch already counted.
        let commits = commits.filter { $0.parents.totalCount <= 1 }
        // Vendored or generated code in one commit would flatten every other week.
        let addedCap = percentile95(commits.map(\.additions)), deletedCap = percentile95(commits.map(\.deletions))
        let iso = ISO8601DateFormatter()
        var added: [Date: Int] = [:], deleted: [Date: Int] = [:]
        for commit in commits {
            guard let date = iso.date(from: commit.committedDate),
                  let week = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { continue }
            added[week, default: 0] += min(commit.additions, addedCap)
            deleted[week, default: 0] += min(commit.deletions, deletedCap)
        }
        let weeks = weekStarts(calendar: calendar, now: now).map {
            GitHubSummary.Week(start: $0, added: added[$0] ?? 0, deleted: deleted[$0] ?? 0)
        }
        let recent = commits.compactMap { commit in
            iso.date(from: commit.committedDate).map {
                GitHubSummary.Commit(oid: commit.oid, repository: commit.source.name,
                                     headline: commit.source.isPrivate && !keepsPrivateHeadlines ? nil : commit.messageHeadline,
                                     date: $0, additions: commit.additions, deletions: commit.deletions)
            }
        }
        // Ties keep the order GitHub gave, most recently pushed first.
        var order: [String] = [], counts: [String: Int] = [:]
        for commit in commits {
            if counts[commit.source.nameWithOwner] == nil { order.append(commit.source.nameWithOwner) }
            counts[commit.source.nameWithOwner, default: 0] += 1
        }
        let ranked = order.enumerated().sorted { (counts[$0.element]!, -$0.offset) > (counts[$1.element]!, -$1.offset) }.map(\.element)

        let levels = ["NONE": 0, "FIRST_QUARTILE": 1, "SECOND_QUARTILE": 2, "THIRD_QUARTILE": 3, "FOURTH_QUARTILE": 4]
        return GitHubSummary(login: summary.viewer.login, contributions: days.map(\.contributionCount),
                             levels: days.map { levels[$0.contributionLevel] ?? 0 }, firstDay: firstDay,
                             openPullRequests: summary.pullRequests.issueCount, reviewRequests: summary.reviewRequests.issueCount,
                             assignedIssues: summary.assignedIssues.issueCount, weeks: weeks, linesTruncated: truncated,
                             commits: Array(recent.sorted { $0.date > $1.date }.prefix(20)), repositories: ranked)
    }

    /// The value at the 95th percentile's index rounded down, so among a few commits
    /// the largest is clamped to the runner-up.
    private static func percentile95(_ values: [Int]) -> Int {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[Int(Double(sorted.count - 1) * 0.95)]
    }
}

extension HTTP {
    public func githubDeviceCode(clientID: String) async throws -> GitHubDeviceFlow.Code {
        try GitHubDeviceFlow.code(from: try await githubForm("https://github.com/login/device/code", [
            "client_id": clientID,
            "scope": "repo read:user",
        ]))
    }

    public func githubToken(clientID: String, code: GitHubDeviceFlow.Code, interval: Int) async throws -> GitHubDeviceFlow.Poll {
        try GitHubDeviceFlow.poll(from: try await githubForm("https://github.com/login/oauth/access_token", [
            "client_id": clientID,
            "device_code": code.deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ]), interval: interval)
    }

    /// The calendar and counts, then twelve weeks of commits, which need the account's
    /// id from the first answer. A busy repository takes more than one page of a hundred.
    /// Private repositories' headlines stay off unless `keepsPrivateHeadlines`, for a
    /// caller that redacts them itself.
    public func github(token: String, calendar: Calendar, now: Date = Date(),
                       keepsPrivateHeadlines: Bool = false) async throws -> GitHubSummary {
        let summary = try await githubGraphQL(GitHubParsing.summaryQuery, variables: [:], token: token)
        struct Account: Decodable { struct Fields: Decodable { struct Viewer: Decodable { var id: String }; var viewer: Viewer }; var data: Fields }
        let variables = [
            "author": try GitHubParsing.decode(Account.self, from: summary).data.viewer.id,
            "since": ISO8601DateFormatter().string(from: GitHubParsing.weekStarts(calendar: calendar, now: now)[0]),
        ]
        let first = try GitHubParsing.histories(from: try await githubGraphQL(GitHubParsing.historyQuery, variables: variables, token: token))
        let (commits, truncated) = try await GitHubParsing.readAll(first, extraPages: 20) { history in
            try GitHubParsing.history(from: try await githubGraphQL(GitHubParsing.pageQuery, variables: variables.merging([
                "repository": history.repository,
                "after": history.next!,
            ]) { $1 }, token: token))
        }
        return try GitHubParsing.summary(from: summary, commits: commits, truncated: truncated, calendar: calendar, now: now,
                                         keepsPrivateHeadlines: keepsPrivateHeadlines)
    }

    /// GitHub's OAuth endpoints give their errors in the body, under a 200 or a 4xx,
    /// so the body is read whatever the status.
    private func githubForm(_ url: String, _ fields: [String: String]) async throws -> Data {
        var request = URLRequest(url: makeURL(url))
        request.httpMethod = "POST"
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var form = URLComponents()
        form.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data(form.percentEncodedQuery!.utf8)
        return try await session.data(for: request).0
    }

    func githubGraphQL(_ query: String, variables: [String: String], token: String) async throws -> Data {
        var request = URLRequest(url: makeURL("https://api.github.com/graphql"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["query": query, "variables": variables])
        return try await send(request)
    }
}
