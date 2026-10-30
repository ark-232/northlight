import Foundation

/// What a coding agent on the Mac is doing right now, as shown on the TV.
/// Mirrors the Claude Code status line: a verb, how long the turn has run, and
/// output tokens so far.
public struct AgentStatus: Codable, Sendable, Equatable, Identifiable {
    public enum Activity: String, Codable, Sendable {
        case idle        // no session running
        case thinking    // reasoning block in flight
        case composing   // writing the reply
        case tool        // a tool call is running
        case waiting     // waiting on the user (permission prompt, question)
    }

    public var id: String { session }
    /// The transcript's own id, so two sessions of one agent stay apart.
    public var session: String
    public var agent: String
    public var activity: Activity
    /// Short label: "Composing", "Thinking", "Editing ICSParser.swift".
    public var verb: String
    public var elapsed: TimeInterval?
    public var outputTokens: Int?
    public var project: String?
    public var branch: String?
    public var thinking: String?
    public var toolName: String?
    public var toolTarget: String?
    /// Subagents writing their own transcripts lately.
    public var subagents: Int
    /// True when this project matched the blocklist and detail was stripped.
    public var redacted: Bool
    public var updatedAt: Date

    public init(
        session: String,
        agent: String,
        activity: Activity,
        verb: String,
        elapsed: TimeInterval? = nil,
        outputTokens: Int? = nil,
        project: String? = nil,
        branch: String? = nil,
        thinking: String? = nil,
        toolName: String? = nil,
        toolTarget: String? = nil,
        subagents: Int = 0,
        redacted: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.session = session
        self.agent = agent
        self.activity = activity
        self.verb = verb
        self.elapsed = elapsed
        self.outputTokens = outputTokens
        self.project = project
        self.branch = branch
        self.thinking = thinking
        self.toolName = toolName
        self.toolTarget = toolTarget
        self.subagents = subagents
        self.redacted = redacted
        self.updatedAt = updatedAt
    }

    /// "2m 29s · ↓ 8.1k tokens", the CLI's own shape.
    public var detailLine: String {
        var parts: [String] = []
        if let elapsed { parts.append(elapsed.shortAge) }
        if let outputTokens { parts.append("↓ \(AgentStatus.compact(outputTokens)) tokens") }
        return parts.joined(separator: " · ")
    }

    static func compact(_ tokens: Int) -> String {
        if tokens < 1_000 { return "\(tokens)" }
        return String(format: "%.1fk", Double(tokens) / 1_000)
    }
}

/// The Mac's latest word on its coding agents, and when it came.
public struct AgentReport: Sendable, Equatable {
    public var statuses: [AgentStatus]
    public var receivedAt: Date

    public init(statuses: [AgentStatus], receivedAt: Date) {
        self.statuses = statuses
        self.receivedAt = receivedAt
    }

    /// How often the Mac repeats a report that has not changed.
    public static let repeatInterval: TimeInterval = 15

    /// The statuses while the Mac keeps talking, or nil once it has missed three
    /// repeats.
    public func statuses(asOf now: Date) -> [AgentStatus]? {
        now.timeIntervalSince(receivedAt) < 3 * Self.repeatInterval ? statuses : nil
    }
}
