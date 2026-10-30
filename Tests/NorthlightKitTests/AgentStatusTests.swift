import Foundation
import Testing
@testable import NorthlightAgent
@testable import NorthlightKit

private let now = Date(timeIntervalSince1970: 1_792_000_000)

private func line(_ object: [String: Any]) -> String {
    String(data: try! JSONSerialization.data(withJSONObject: object), encoding: .utf8)!
}

private func stamp(_ offset: TimeInterval) -> String {
    let fmt = ISO8601DateFormatter()
    fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    fmt.timeZone = TimeZone(identifier: "UTC")
    return fmt.string(from: now.addingTimeInterval(offset))
}

private func assistant(_ block: [String: Any], tokens: Int, offset: TimeInterval, cwd: String, id: String? = nil) -> String {
    var message: [String: Any] = ["usage": ["output_tokens": tokens], "content": [block]]
    message["id"] = id
    return line([
        "type": "assistant",
        "timestamp": stamp(offset),
        "cwd": cwd,
        "gitBranch": "main",
        "message": message,
    ])
}

/// Claude Code records each tool's result as a user entry.
private func toolResult(offset: TimeInterval) -> String {
    line(["type": "user", "timestamp": stamp(offset),
          "message": ["role": "user", "content": [["type": "tool_result", "tool_use_id": "t", "content": "ok"]]]])
}

/// The reader with nothing blocked unless a test lists fragments.
private func read(_ lines: [String], blocking fragments: [String] = []) -> AgentStatus? {
    TranscriptReader.status(fromLines: lines, session: "s1", now: now, redaction: AgentRedaction(blockedPathFragments: fragments))
}

// MARK: - Status derivation

@Test func derivesComposingWithElapsedAndTokens() throws {
    let lines = [
        line(["type": "user", "timestamp": stamp(-150)]),
        line(["type": "api-request", "timestamp": stamp(-149)]),
        assistant(["type": "thinking", "thinking": "weighing options"], tokens: 400, offset: -120, cwd: "/Users/x/Development/northlight"),
        assistant(["type": "text", "text": "Here is the plan"], tokens: 8_100, offset: -30, cwd: "/Users/x/Development/northlight"),
    ]

    let status = try #require(read(lines))
    #expect(status.activity == .composing)
    #expect(status.verb == "Composing")
    #expect(status.outputTokens == 8_500)
    #expect(status.project == "northlight")
    #expect(status.branch == "main")
    // Turn began at the first timestamped entry after the user message.
    #expect(Int(status.elapsed!) == 150)
    #expect(status.redacted == false)
    #expect(status.id == "s1")
}

@Test func detailLineMatchesTheCLIShape() {
    let status = AgentStatus(session: "s1", agent: "Claude Code", activity: .composing, verb: "Composing",
                             elapsed: 149, outputTokens: 8_100)
    #expect(status.detailLine == "2m · ↓ 8.1k tokens")

    let small = AgentStatus(session: "s2", agent: "a", activity: .tool, verb: "Running", elapsed: 42, outputTokens: 850)
    #expect(small.detailLine == "42s · ↓ 850 tokens")
}

@Test func toolCallBecomesAReadableVerb() throws {
    let lines = [
        line(["type": "user", "timestamp": stamp(-20)]),
        assistant(["type": "tool_use", "name": "Edit", "input": ["file_path": "/a/b/ICSParser.swift"]],
                  tokens: 10, offset: -5, cwd: "/Users/x/Development/northlight"),
    ]
    let status = try #require(read(lines))
    #expect(status.activity == .tool)
    #expect(status.verb == "Editing ICSParser.swift")
    #expect(status.toolName == "Edit")
    #expect(status.toolTarget == "ICSParser.swift")
}

@Test func bashUsesItsDescriptionNotTheRawCommand() throws {
    let lines = [
        line(["type": "user", "timestamp": stamp(-20)]),
        assistant(["type": "tool_use", "name": "Bash",
                   "input": ["command": "swift test --verbose", "description": "Run the test suite"]],
                  tokens: 10, offset: -5, cwd: "/Users/x/Development/northlight"),
    ]
    let status = try #require(read(lines))
    #expect(status.verb == "Running Run the test suite")
}

@Test func onlyTheCurrentTurnCounts() throws {
    let lines = [
        line(["type": "user", "timestamp": stamp(-900)]),
        assistant(["type": "text", "text": "old"], tokens: 5_000, offset: -880, cwd: "/Users/x/Development/northlight"),
        line(["type": "user", "timestamp": stamp(-60)]),
        assistant(["type": "text", "text": "new"], tokens: 120, offset: -40, cwd: "/Users/x/Development/northlight"),
    ]
    let status = try #require(read(lines))
    // The 5,000 tokens from the previous turn must not be included.
    #expect(status.outputTokens == 120)
    #expect(Int(status.elapsed!) == 60)
}

@Test func aQuietTranscriptReadsAsIdle() throws {
    let lines = [
        line(["type": "user", "timestamp": stamp(-4_000)]),
        assistant(["type": "thinking", "thinking": "secret reasoning"], tokens: 50, offset: -3_900, cwd: "/Users/x/Development/northlight"),
    ]
    let status = try #require(read(lines))
    #expect(status.activity == .idle)
    #expect(status.verb == "Idle")
    // A stale thinking block must not linger on screen.
    #expect(status.thinking == nil)
}

@Test func toolResultsDoNotStartATurn() throws {
    let lines = [
        line(["type": "user", "timestamp": stamp(-300), "message": ["role": "user", "content": "Fix the build"]]),
        assistant(["type": "tool_use", "name": "Bash", "input": ["command": "swift build", "description": "Build"]],
                  tokens: 40, offset: -290, cwd: "/Users/x/Development/northlight"),
        toolResult(offset: -200),
        assistant(["type": "text", "text": "Built"], tokens: 60, offset: -10, cwd: "/Users/x/Development/northlight"),
    ]
    let status = try #require(read(lines))
    #expect(Int(status.elapsed!) == 300)
    #expect(status.outputTokens == 100)
}

@Test func aResponseSplitAcrossEntriesCountsItsTokensOnce() throws {
    // Each content block of a response is its own entry, carrying the whole response's usage.
    let lines = [
        line(["type": "user", "timestamp": stamp(-30)]),
        assistant(["type": "thinking", "thinking": "plan"], tokens: 1_127, offset: -20, cwd: "/Users/x", id: "msg_1"),
        assistant(["type": "tool_use", "name": "Read", "input": ["file_path": "/a/Plan.md"]], tokens: 1_127, offset: -20,
                  cwd: "/Users/x", id: "msg_1"),
    ]
    #expect(try #require(read(lines)).outputTokens == 1_127)
}

@Test func aTurnThatBeganBeforeTheLinesHasNoTimerOrCount() throws {
    // The tail of a long transcript can open mid-turn, after a tool result.
    let lines = [
        toolResult(offset: -200),
        assistant(["type": "text", "text": "still going"], tokens: 60, offset: -10, cwd: "/Users/x/Development/northlight"),
    ]
    let status = try #require(read(lines))
    #expect(status.activity == .composing)
    #expect(status.elapsed == nil)
    #expect(status.outputTokens == nil)
}

@Test func aNamedSessionGoesByItsName() throws {
    let lines = [
        line(["type": "agent-name", "agentName": "widget-canvas"]),
        line(["type": "user", "timestamp": stamp(-30)]),
        assistant(["type": "text", "text": "a"], tokens: 1, offset: -20, cwd: "/Users/x"),
    ]
    #expect(try #require(read(lines)).project == "widget-canvas")
}

@Test func aSessionIsRedactedByItsNameAndTheFilesItTouches() throws {
    // Run from the home directory, the working directory says nothing.
    let touching = [
        line(["type": "user", "timestamp": stamp(-30)]),
        assistant(["type": "tool_use", "name": "Read", "input": ["file_path": "/Users/x/Notes/Private/notes.md"]],
                  tokens: 5, offset: -20, cwd: "/Users/x"),
        assistant(["type": "thinking", "thinking": "the notes say"], tokens: 5, offset: -10, cwd: "/Users/x"),
    ]
    let status = try #require(read(touching, blocking: ["Private"]))
    #expect(status.redacted && status.thinking == nil && status.project == nil)

    let running = [
        line(["type": "user", "timestamp": stamp(-30)]),
        assistant(["type": "tool_use", "name": "Bash", "input": ["command": "ls ~/Documents/taxes-2026", "description": "List"]],
                  tokens: 5, offset: -20, cwd: "/Users/x"),
    ]
    #expect(try #require(read(running, blocking: ["taxes-2026"])).redacted)

    let named = [
        line(["type": "agent-name", "agentName": "client-contract-review"]),
        line(["type": "user", "timestamp": stamp(-30)]),
        assistant(["type": "text", "text": "a"], tokens: 1, offset: -20, cwd: "/Users/x"),
    ]
    #expect(try #require(read(named, blocking: ["client-contract"])).redacted)
}

@Test func malformedLinesAreSkippedNotFatal() {
    #expect(read([]) == nil)
    #expect(read(["not json", "{bad"]) == nil)
}

@Test func thinkingExcerptKeepsTheTail() {
    let long = String(repeating: "a", count: 100) + " THE CURRENT THOUGHT"
    let excerpt = try! #require(TranscriptReader.excerpt(long, limit: 30))
    #expect(excerpt.hasPrefix("…"))
    #expect(excerpt.hasSuffix("THE CURRENT THOUGHT"))
}

// MARK: - Redaction

@Test func sensitiveProjectsAreStripped() throws {
    let lines = [
        line(["type": "user", "timestamp": stamp(-20)]),
        assistant(["type": "thinking", "thinking": "case details"], tokens: 300, offset: -5,
                  cwd: "/Users/x/Notes/Private/journal"),
    ]
    let status = try #require(read(lines, blocking: ["Private"]))
    #expect(status.redacted)
    #expect(status.thinking == nil)
    #expect(status.project == nil)
    #expect(status.branch == nil)
    #expect(status.verb == "Working")
    // The shape of the activity survives, so the tile still reads as busy.
    #expect(status.outputTokens == 300)
    #expect(status.elapsed != nil)
}

@Test func blocklistMatchesNestedPathsAndIsCaseInsensitive() {
    let r = AgentRedaction(blockedPathFragments: ["Private", "client-contract", "taxes-2026", "Medical"])
    #expect(r.isBlocked(path: "/Users/x/Notes/Private/notes"))
    #expect(r.isBlocked(path: "/Users/x/notes/private/deep/nested/dir"))
    #expect(r.isBlocked(path: "/Users/x/Development/client-contract"))
    #expect(r.isBlocked(path: "/Users/x/Documents/taxes-2026/receipts"))
    #expect(r.isBlocked(path: "/Users/x/anything/Medical-Records"))
    #expect(!r.isBlocked(path: "/Users/x/Development/northlight"))
    #expect(!r.isBlocked(path: nil))
}

@Test func redactionLeavesAllowedProjectsIntact() throws {
    let lines = [
        line(["type": "user", "timestamp": stamp(-20)]),
        assistant(["type": "thinking", "thinking": "picking a layout"], tokens: 300, offset: -5,
                  cwd: "/Users/x/Development/northlight"),
    ]
    let status = try #require(read(lines))
    #expect(!status.redacted)
    #expect(status.thinking == "picking a layout")
    #expect(status.project == "northlight")
}

@Test func aSessionStaysRedactedOnceItTouchesABlockedPath() throws {
    // A later turn can quote what an earlier one read.
    let lines = [
        line(["type": "user", "timestamp": stamp(-300)]),
        assistant(["type": "tool_use", "name": "Read", "input": ["file_path": "/Users/x/Notes/Private/notes.md"]],
                  tokens: 5, offset: -290, cwd: "/Users/x"),
        toolResult(offset: -280),
        line(["type": "user", "timestamp": stamp(-60), "message": ["role": "user", "content": "summarize it"]]),
        assistant(["type": "thinking", "thinking": "the notes say"], tokens: 5, offset: -10, cwd: "/Users/x"),
    ]
    let status = try #require(read(lines, blocking: ["Private"]))
    #expect(status.redacted && status.thinking == nil)
}

@Test func whatTheTileWouldShowIsCheckedToo() throws {
    // A command's description and the reasoning are on screen, so they are matched as well.
    let described = [
        line(["type": "user", "timestamp": stamp(-30)]),
        assistant(["type": "tool_use", "name": "Bash", "input": ["command": "make draft", "description": "Draft the lease"]],
                  tokens: 5, offset: -20, cwd: "/Users/x/Development/site"),
    ]
    #expect(try #require(read(described, blocking: ["Lease"])).redacted)

    let reasoning = [
        line(["type": "user", "timestamp": stamp(-30)]),
        assistant(["type": "thinking", "thinking": "The lease's second page needs"], tokens: 5, offset: -20, cwd: "/Users/x"),
    ]
    #expect(try #require(read(reasoning, blocking: ["Lease"])).redacted)
}

@Test func aToolStillRunningKeepsTheSessionBusy() throws {
    // A long build writes nothing until it ends.
    let lines = [
        line(["type": "user", "timestamp": stamp(-600)]),
        assistant(["type": "tool_use", "name": "Bash", "input": ["command": "swift test", "description": "Run the tests"]],
                  tokens: 30, offset: -500, cwd: "/Users/x/Development/northlight"),
    ]
    let status = try #require(read(lines))
    #expect(status.activity == .tool)
    #expect(status.verb == "Running Run the tests")
    #expect(Int(status.elapsed!) == 600)
}

@Test func subagentTranscriptsAreDistinguishedFromTheMainSession() {
    // Workflow helpers write agent-<id>.jsonl next to the session's own
    // <uuid>.jsonl. Picking the newest file blindly reports a helper, not you.
    #expect(TranscriptReader.isSubagentTranscript("agent-a0a51c6fb937579a4.jsonl"))
    #expect(!TranscriptReader.isSubagentTranscript("7ac21289-7ff6-4ed2-b7f4-dc350df652eb.jsonl"))
}

@Test func idleSessionsReportNoElapsedTimer() throws {
    let lines = [
        line(["type": "user", "timestamp": stamp(-5_000)]),
        assistant(["type": "text", "text": "done"], tokens: 20, offset: -4_900, cwd: "/Users/x/Development/northlight"),
    ]
    let status = try #require(read(lines))
    #expect(status.activity == .idle)
    // A stopped turn must not keep counting up on screen.
    #expect(status.elapsed == nil)
    #expect(status.detailLine == "↓ 20 tokens")
}
