import Foundation

/// What is waiting on the viewer: unread notifications, pull requests asking for
/// their review, and their own open pull requests with how review and checks stand.
public struct GitHubInbox: Codable, Sendable, Equatable {
    /// Unread notification threads, counted up to the 50 one request returns.
    public var unread: Int
    /// True when more unread threads exist than `unread` counts.
    public var moreUnread: Bool
    /// The newest unread threads, newest first, at most ten.
    public var notifications: [Notification]
    /// Open pull requests asking for the viewer's review, newest first.
    public var reviewRequests: [PullRequest]
    public var reviewRequestCount: Int
    /// The viewer's own open pull requests, newest first.
    public var authored: [PullRequest]
    public var authoredCount: Int

    public init(unread: Int, moreUnread: Bool, notifications: [Notification], reviewRequests: [PullRequest],
                reviewRequestCount: Int, authored: [PullRequest], authoredCount: Int) {
        self.unread = unread
        self.moreUnread = moreUnread
        self.notifications = notifications
        self.reviewRequests = reviewRequests
        self.reviewRequestCount = reviewRequestCount
        self.authored = authored
        self.authoredCount = authoredCount
    }

    public struct Notification: Codable, Sendable, Equatable {
        public var id: String
        /// The repository's name without its owner.
        public var repository: String
        /// Nil for a private repository, unless the Mac fetched it and redacted it there.
        public var title: String?
        public var kind: Kind
        /// GitHub's word for why it came, such as "review_requested" or "mention".
        public var reason: String
        /// The issue or pull request's number, when it has one.
        public var number: Int?
        public var updatedAt: Date

        public init(id: String, repository: String, title: String?, kind: Kind, reason: String, number: Int?, updatedAt: Date) {
            self.id = id
            self.repository = repository
            self.title = title
            self.kind = kind
            self.reason = reason
            self.number = number
            self.updatedAt = updatedAt
        }
    }

    public enum Kind: String, Codable, Sendable {
        case pullRequest, issue, release, checkSuite, discussion, commit, other

        /// A kind a newer Mac knows reads as `other` here.
        public init(from decoder: any Decoder) throws {
            self = Kind(rawValue: try decoder.singleValueContainer().decode(String.self)) ?? .other
        }

        init(subjectType: String) {
            self = switch subjectType {
            case "PullRequest": .pullRequest
            case "Issue": .issue
            case "Release": .release
            case "CheckSuite": .checkSuite
            case "Discussion": .discussion
            case "Commit": .commit
            default: .other
            }
        }
    }

    public struct PullRequest: Codable, Sendable, Equatable {
        public var repository: String
        public var number: Int
        /// Nil for a private repository, as a notification's title is.
        public var title: String?
        public var updatedAt: Date
        public var isDraft: Bool
        public var review: Review
        public var checks: Checks

        public init(repository: String, number: Int, title: String?, updatedAt: Date, isDraft: Bool, review: Review, checks: Checks) {
            self.repository = repository
            self.number = number
            self.title = title
            self.updatedAt = updatedAt
            self.isDraft = isDraft
            self.review = review
            self.checks = checks
        }
    }

    public enum Review: String, Codable, Sendable {
        case approved, changesRequested, required, none
    }

    public enum Checks: String, Codable, Sendable {
        case passing, failing, pending, none
    }
}

enum GitHubInboxParsing {
    static let pullRequestsQuery = """
    query {
      reviewRequested: search(query: "is:pr is:open archived:false review-requested:@me", type: ISSUE, first: 10) {
        issueCount nodes { ...pull }
      }
      authored: search(query: "is:pr is:open archived:false author:@me", type: ISSUE, first: 10) {
        issueCount nodes { ...pull }
      }
    }
    fragment pull on PullRequest {
      number title isDraft updatedAt reviewDecision
      repository { name isPrivate }
      commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
    }
    """

    /// The newest ten unread threads and how many there were. The repository's
    /// `private` flag withholds the title unless `keepsPrivateTitles`.
    static func notifications(from data: Data, keepsPrivateTitles: Bool) throws -> (unread: Int, newest: [GitHubInbox.Notification]) {
        struct Thread: Decodable {
            struct Subject: Decodable { var title: String; var url: String?; var type: String }
            struct Repository: Decodable { var name: String; var `private`: Bool }
            var id: String
            var unread: Bool
            var reason: String
            var updated_at: String
            var subject: Subject
            var repository: Repository
        }
        let iso = ISO8601DateFormatter()
        let threads = try decodeFeed([Thread].self, from: data).filter(\.unread)
        let newest = threads.compactMap { thread -> GitHubInbox.Notification? in
            guard let updated = iso.date(from: thread.updated_at) else { return nil }
            return GitHubInbox.Notification(
                id: thread.id, repository: thread.repository.name,
                title: thread.repository.private && !keepsPrivateTitles ? nil : thread.subject.title,
                kind: GitHubInbox.Kind(subjectType: thread.subject.type), reason: thread.reason,
                number: thread.subject.url.flatMap(number(in:)), updatedAt: updated)
        }
        return (threads.count, Array(newest.sorted { $0.updatedAt > $1.updatedAt }.prefix(10)))
    }

    /// The number at the end of an issue, pull request or discussion's address; a
    /// release's address ends in an id, not a number anyone uses.
    private static func number(in url: String) -> Int? {
        guard ["/pulls/", "/issues/", "/discussions/"].contains(where: url.contains) else { return nil }
        return url.split(separator: "/").last.flatMap { Int($0) }
    }

    static func pullRequests(from data: Data, keepsPrivateTitles: Bool)
        throws -> (reviewRequests: [GitHubInbox.PullRequest], reviewCount: Int, authored: [GitHubInbox.PullRequest], authoredCount: Int) {
        struct Node: Decodable {
            struct Repository: Decodable { var name: String; var isPrivate: Bool }
            struct Commits: Decodable { var nodes: [Last?] }
            struct Last: Decodable { var commit: Commit }
            struct Commit: Decodable { var statusCheckRollup: Rollup? }
            struct Rollup: Decodable { var state: String }
            // A search hit that is not a pull request comes back as an empty object.
            var number: Int?
            var title: String?
            var isDraft: Bool?
            var updatedAt: String?
            var reviewDecision: String?
            var repository: Repository?
            var commits: Commits?
        }
        struct Search: Decodable { var issueCount: Int; var nodes: [Node?] }
        struct Answer: Decodable { struct Fields: Decodable { var reviewRequested: Search; var authored: Search }; var data: Fields }
        let iso = ISO8601DateFormatter()
        func pulls(_ search: Search) -> [GitHubInbox.PullRequest] {
            search.nodes.compactMap { node in
                guard let node, let number = node.number, let repository = node.repository,
                      let updated = node.updatedAt.flatMap(iso.date(from:)) else { return nil }
                let checks: GitHubInbox.Checks = switch node.commits?.nodes.last??.commit.statusCheckRollup?.state {
                case "SUCCESS": .passing
                case "FAILURE", "ERROR": .failing
                case "PENDING", "EXPECTED": .pending
                default: .none
                }
                let review: GitHubInbox.Review = switch node.reviewDecision {
                case "APPROVED": .approved
                case "CHANGES_REQUESTED": .changesRequested
                case "REVIEW_REQUIRED": .required
                default: .none
                }
                return GitHubInbox.PullRequest(repository: repository.name, number: number,
                                               title: repository.isPrivate && !keepsPrivateTitles ? nil : node.title,
                                               updatedAt: updated, isDraft: node.isDraft ?? false, review: review, checks: checks)
            }.sorted { $0.updatedAt > $1.updatedAt }
        }
        let answer = try GitHubParsing.decode(Answer.self, from: data).data
        return (pulls(answer.reviewRequested), answer.reviewRequested.issueCount, pulls(answer.authored), answer.authored.issueCount)
    }
}

/// The notifications last read, so the next read can ask GitHub whether anything
/// changed since, and waits as long as GitHub's X-Poll-Interval asks.
public actor GitHubNotificationPoll {
    var lastModified: String?
    var unread = 0
    var more = false
    var newest: [GitHubInbox.Notification] = []
    var notBefore = Date.distantPast

    public init() {}

    func read(http: HTTP, token: String, keepsPrivateTitles: Bool, now: Date) async throws
        -> (unread: Int, more: Bool, newest: [GitHubInbox.Notification]) {
        guard now >= notBefore else { return (unread, more, newest) }
        var request = URLRequest(url: makeURL("https://api.github.com/notifications", ["per_page": "50"]))
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(http.userAgent, forHTTPHeaderField: "User-Agent")
        // Without this, URLSession would answer a 304 from its own cache as a 200.
        request.cachePolicy = .reloadIgnoringLocalCacheData
        if let lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }
        let (data, response) = try await http.session.data(for: request)
        let answer = response as? HTTPURLResponse
        if let seconds = answer?.value(forHTTPHeaderField: "X-Poll-Interval").flatMap(TimeInterval.init) {
            notBefore = now.addingTimeInterval(seconds)
        }
        switch answer?.statusCode ?? 0 {
        case 304:
            break
        case 200..<300:
            (unread, newest) = try GitHubInboxParsing.notifications(from: data, keepsPrivateTitles: keepsPrivateTitles)
            more = answer?.value(forHTTPHeaderField: "Link")?.contains(#"rel="next""#) == true
            lastModified = answer?.value(forHTTPHeaderField: "Last-Modified")
        case let status:
            throw FeedError.badStatus(status)
        }
        return (unread, more, newest)
    }
}

extension HTTP {
    /// Unread notifications, asked only when GitHub's poll interval allows and
    /// answered from `poll` when nothing changed, and the pull requests waiting on
    /// the viewer and theirs. Private repositories' titles stay off unless
    /// `keepsPrivateTitles`, for a caller that redacts them itself.
    public func githubInbox(token: String, poll: GitHubNotificationPoll, keepsPrivateTitles: Bool = false,
                            now: Date = Date()) async throws -> GitHubInbox {
        let notifications = try await poll.read(http: self, token: token, keepsPrivateTitles: keepsPrivateTitles, now: now)
        let pulls = try GitHubInboxParsing.pullRequests(from: try await githubGraphQL(GitHubInboxParsing.pullRequestsQuery,
                                                                                      variables: [:], token: token),
                                                        keepsPrivateTitles: keepsPrivateTitles)
        return GitHubInbox(unread: notifications.unread, moreUnread: notifications.more, notifications: notifications.newest,
                           reviewRequests: pulls.reviewRequests, reviewRequestCount: pulls.reviewCount,
                           authored: pulls.authored, authoredCount: pulls.authoredCount)
    }
}
