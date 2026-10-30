import Foundation
import Testing
@testable import NorthlightAgent
@testable import NorthlightKit

private let now = Date()

private func entry(_ object: [String: Any]) -> String {
    String(decoding: try! JSONSerialization.data(withJSONObject: object), as: UTF8.self)
}

private func stamp(_ offset: TimeInterval) -> String {
    ISO8601DateFormatter().string(from: now.addingTimeInterval(offset))
}

/// A prompt and a reply, the reply `ago` seconds before now.
private func turn(ago: TimeInterval, cwd: String) -> String {
    [entry(["type": "user", "timestamp": stamp(-ago - 30)]),
     entry(["type": "assistant", "timestamp": stamp(-ago), "cwd": cwd,
            "message": ["id": "m", "usage": ["output_tokens": 50], "content": [["type": "text", "text": "ok"]]]])]
        .joined(separator: "\n") + "\n"
}

private func write(_ text: String, to url: URL, modified: Date) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(text.utf8).write(to: url)
    try FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: url.path)
}

private func projectsRoot() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appending(path: "watcher-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

/// The tile lists every session from the last twelve hours, quiet ones as idle.
@Test func recentSessionsAreListedAndQuietOnesReadIdle() async throws {
    let root = try projectsRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try write(turn(ago: 5, cwd: "/Users/x/a"), to: root.appending(path: "a/s1.jsonl"), modified: now)
    try write(turn(ago: 600, cwd: "/Users/x/a"), to: root.appending(path: "a/s2.jsonl"), modified: now - 600)
    try write(turn(ago: 5, cwd: "/Users/x/b"), to: root.appending(path: "b/s3.jsonl"), modified: now)
    try write(turn(ago: 13 * 3_600, cwd: "/Users/x/b"), to: root.appending(path: "b/s4.jsonl"), modified: now - 13 * 3_600)
    // Subagents write their own transcripts beside the session's, a workflow's a level down.
    try write(turn(ago: 5, cwd: "/Users/x/a"), to: root.appending(path: "a/s1/subagents/agent-1.jsonl"), modified: now)
    try write(turn(ago: 600, cwd: "/Users/x/a"), to: root.appending(path: "a/s1/subagents/agent-2.jsonl"), modified: now - 600)
    try write(turn(ago: 5, cwd: "/Users/x/a"), to: root.appending(path: "a/s1/subagents/workflows/wf_1/agent-3.jsonl"), modified: now)

    let watcher = SessionWatcher(root: root, redaction: AgentRedaction(blockedPathFragments: []))
    let statuses = await watcher.statuses(now: now)
    #expect(Set(statuses.map(\.id)) == ["s1", "s2", "s3"])
    #expect(statuses.first { $0.id == "s2" }?.activity == .idle)
    #expect(statuses.first { $0.id == "s1" }?.subagents == 2)
    #expect(statuses.first { $0.id == "s3" }?.project == "b")
}

@Test func aLongTurnIsTimedFromItsPrompt() async throws {
    let root = try projectsRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    // An hour-old prompt, then more filler than the tail holds, then the current reply.
    let filler = (0..<4_000).map { _ in entry(["type": "attachment", "timestamp": stamp(-1_800), "pad": String(repeating: "x", count: 300)]) }
    let text = entry(["type": "user", "timestamp": stamp(-3_600)]) + "\n" + filler.joined(separator: "\n") + "\n" + turn(ago: 5, cwd: "/Users/x/a")
        .split(separator: "\n").last! + "\n"
    try write(text, to: root.appending(path: "a/long.jsonl"), modified: now)

    let watcher = SessionWatcher(root: root, redaction: AgentRedaction(blockedPathFragments: []))
    let status = try #require(await watcher.statuses(now: now).first)
    #expect(status.activity == .composing)
    #expect(Int(status.elapsed!) == 3_600)
}

@Test func aGrowingTranscriptIsReadOnFromWhereItWas() async throws {
    let root = try projectsRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let url = root.appending(path: "a/s1.jsonl")
    try write(turn(ago: 20, cwd: "/Users/x/a"), to: url, modified: now)
    let watcher = SessionWatcher(root: root, redaction: AgentRedaction(blockedPathFragments: []))
    #expect(await watcher.statuses(now: now).first?.verb == "Composing")

    let edit = entry(["type": "assistant", "timestamp": stamp(-2), "cwd": "/Users/x/a",
                      "message": ["id": "m2", "usage": ["output_tokens": 70],
                                  "content": [["type": "tool_use", "name": "Edit", "input": ["file_path": "/x/Plan.swift"]]]]])
    let file = try FileHandle(forWritingTo: url)
    try file.seekToEnd()
    try file.write(contentsOf: Data((edit + "\n").utf8))
    try file.close()
    let status = try #require(await watcher.statuses(now: now).first)
    #expect(status.verb == "Editing Plan.swift")
    #expect(status.outputTokens == 120)
}

@Test func aSessionRunningALongToolStaysListed() async throws {
    let root = try projectsRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let running = [entry(["type": "user", "timestamp": stamp(-330)]),
                   entry(["type": "assistant", "timestamp": stamp(-300), "cwd": "/Users/x/a",
                          "message": ["id": "m", "usage": ["output_tokens": 9],
                                      "content": [["type": "tool_use", "name": "Bash", "input": ["command": "make", "description": "Build"]]]]])]
        .joined(separator: "\n") + "\n"
    let url = root.appending(path: "a/s1.jsonl")
    try write(running, to: url, modified: now)
    let watcher = SessionWatcher(root: root, redaction: AgentRedaction(blockedPathFragments: []))
    _ = await watcher.statuses(now: now)

    // The build has written nothing for five minutes.
    try FileManager.default.setAttributes([.modificationDate: now - 300], ofItemAtPath: url.path)
    #expect(await watcher.statuses(now: now).map(\.verb) == ["Running Build"])
}
