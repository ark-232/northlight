import Foundation
import NorthlightKit

/// One Claude Code session, read line by line as its transcript grows, so a long
/// turn costs only what it appends.
///
/// The transcript is newline-delimited JSON, one object per line. The shape used
/// here, confirmed against live sessions:
///   - `user` entries are the person's prompts, the harness's own meta entries,
///     and each tool's result
///   - `assistant` entries carry one `message.content[]` block each, typed
///     `thinking`, `text` or `tool_use`; a response's blocks share its
///     `message.id` and repeat its `message.usage`
///   - `agent-name` entries repeat the session's name
///   - `cwd` and `gitBranch` sit at the top level of an entry
public struct Transcript: Sendable {
    public let session: String
    private let redaction: AgentRedaction

    /// The current turn, from the person's last prompt.
    private struct Turn: Sendable {
        var start: Date?
        var prompted = false
        var outputTokens = 0
        var counted: Set<String> = []
        var activity = AgentStatus.Activity.idle
        var verb = "Idle"
        var thinking: String?
        var toolName: String?
        var toolTarget: String?
        var toolRunning = false
    }

    private var turn = Turn()
    private var name: String?
    private var cwd: String?
    private var branch: String?
    private var lastStamp: Date?
    /// Set for good once anything the session showed or touched matches the list,
    /// since a later turn can quote what an earlier one read.
    private var blocked = false

    /// A tool call with no result yet, which can run for a long time in silence.
    public var toolRunning: Bool { turn.toolRunning }

    public init(session: String, redaction: AgentRedaction) {
        self.session = session
        self.redaction = redaction
    }

    public mutating func read(_ line: some StringProtocol) {
        guard let entry = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any] else { return }
        let type = entry["type"] as? String
        let stamp = (entry["timestamp"] as? String).flatMap(TranscriptReader.date)
        if let stamp { lastStamp = stamp }
        if type == "agent-name", let agentName = entry["agentName"] as? String {
            name = agentName
            check(agentName)
        }
        if let dir = entry["cwd"] as? String {
            cwd = dir
            check(dir)
        }
        if let gitBranch = entry["gitBranch"] as? String, !gitBranch.isEmpty {
            branch = gitBranch
            check(gitBranch)
        }

        if TranscriptReader.isPrompt(entry) {
            turn = Turn(start: stamp, prompted: true)
            return
        }
        if turn.start == nil { turn.start = stamp }
        guard let message = entry["message"] as? [String: Any], let blocks = message["content"] as? [[String: Any]] else { return }
        if type == "user", blocks.contains(where: { ($0["type"] as? String) == "tool_result" }) {
            turn.toolRunning = false
        }
        guard type == "assistant" else { return }

        if let usage = message["usage"] as? [String: Any], let tokens = usage["output_tokens"] as? Int,
           (message["id"] as? String).map({ turn.counted.insert($0).inserted }) ?? true {
            turn.outputTokens += tokens
        }
        for block in blocks {
            switch block["type"] as? String {
            case "thinking":
                turn.activity = .thinking
                turn.verb = "Thinking"
                if let text = block["thinking"] as? String {
                    turn.thinking = TranscriptReader.excerpt(text)
                    check(text)
                }
            case "text":
                turn.activity = .composing
                turn.verb = "Composing"
            case "tool_use":
                let input = block["input"] as? [String: Any]
                turn.activity = .tool
                turn.toolName = block["name"] as? String
                turn.toolTarget = TranscriptReader.target(from: input)
                turn.verb = TranscriptReader.describe(tool: turn.toolName, target: turn.toolTarget)
                turn.toolRunning = true
                for text in input.map({ TranscriptReader.strings(in: $0) }) ?? [] { check(text) }
            default:
                break
            }
        }
    }

    /// The session at `now`, or nil before any entry.
    public func status(now: Date = Date()) -> AgentStatus? {
        guard let lastStamp else { return nil }
        // A quiet transcript is an idle session, unless a tool is still running.
        let idle = now.timeIntervalSince(lastStamp) > TranscriptReader.liveWindow && !turn.toolRunning
        let status = AgentStatus(
            session: session,
            agent: "Claude Code",
            activity: idle ? .idle : turn.activity,
            verb: idle ? "Idle" : turn.verb,
            // Without the turn's prompt its length and token count are unknown, and an
            // idle session has no running turn to time.
            elapsed: idle || !turn.prompted ? nil : turn.start.map { now.timeIntervalSince($0) },
            outputTokens: turn.prompted && turn.outputTokens > 0 ? turn.outputTokens : nil,
            project: name ?? cwd.map { ($0 as NSString).lastPathComponent },
            branch: branch,
            thinking: idle ? nil : turn.thinking,
            toolName: turn.toolName,
            toolTarget: turn.toolTarget,
            updatedAt: lastStamp
        )
        return blocked ? redaction.redact(status) : status
    }

    private mutating func check(_ text: String) {
        if !blocked, redaction.isBlocked(path: text) { blocked = true }
    }
}

public enum TranscriptReader {

    /// How long after the last entry a session is still considered live.
    public static let liveWindow: TimeInterval = 90

    /// The status a whole run of lines describes.
    public static func status(fromLines lines: [String], session: String, now: Date = Date(),
                              redaction: AgentRedaction) -> AgentStatus? {
        var transcript = Transcript(session: session, redaction: redaction)
        lines.forEach { transcript.read($0) }
        return transcript.status(now: now)
    }

    static func date(_ raw: String) -> Date? {
        (try? Date.ISO8601FormatStyle(includingFractionalSeconds: true).parse(raw)) ?? (try? Date.ISO8601FormatStyle().parse(raw))
    }

    /// Every string in a tool's input, however deep.
    static func strings(in value: Any) -> [String] {
        switch value {
        case let text as String: [text]
        case let list as [Any]: list.flatMap(strings)
        case let object as [String: Any]: object.values.flatMap(strings)
        default: []
        }
    }

    /// The person's prompt: a user entry that is neither the harness's own nor only
    /// a tool's result.
    static func isPrompt(_ entry: [String: Any]) -> Bool {
        guard (entry["type"] as? String) == "user", (entry["isMeta"] as? Bool) != true else { return false }
        guard let blocks = (entry["message"] as? [String: Any])?["content"] as? [[String: Any]] else { return true }
        return blocks.contains { ($0["type"] as? String) != "tool_result" }
    }

    /// Workflow and Agent subagents get their own transcript, named `agent-*`.
    /// The main session is the one worth showing; subagents are counted instead,
    /// or the tile reports whichever helper happened to write last.
    public static func isSubagentTranscript(_ filename: String) -> Bool {
        filename.hasPrefix("agent-")
    }

    /// A tool call's most informative argument, as a short label.
    static func target(from input: [String: Any]?) -> String? {
        guard let input else { return nil }
        if let path = input["file_path"] as? String {
            return (path as NSString).lastPathComponent
        }
        for key in ["description", "pattern", "query", "command"] {
            if let value = input[key] as? String, !value.isEmpty {
                return String(value.prefix(60))
            }
        }
        return nil
    }

    static func describe(tool: String?, target: String?) -> String {
        guard let tool else { return "Working" }
        let verb: String
        switch tool {
        case "Edit", "Write", "NotebookEdit": verb = "Editing"
        case "Read": verb = "Reading"
        case "Bash": verb = "Running"
        case "Grep", "Glob": verb = "Searching"
        case "Agent", "Task": verb = "Delegating"
        case "WebFetch", "WebSearch": verb = "Researching"
        default: verb = tool
        }
        guard let target else { return verb }
        return "\(verb) \(target)"
    }

    /// Thinking blocks run long; the tile shows the tail, which is where the
    /// current reasoning actually is.
    static func excerpt(_ text: String, limit: Int = 240) -> String? {
        let collapsed = text
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !collapsed.isEmpty else { return nil }
        if collapsed.count <= limit { return collapsed }
        return "…" + String(collapsed.suffix(limit))
    }
}
