import Foundation
import NorthlightKit

/// Finds the Claude Code sessions running on this Mac, under the projects folder
/// Claude Code writes one transcript per session into, and keeps reading each as it
/// grows.
public actor SessionWatcher {
    public let root: URL
    private var redaction: AgentRedaction
    /// The sessions read so far, and how far into each file.
    private var sessions: [URL: (transcript: Transcript, offset: UInt64)] = [:]

    /// How long a quiet session with a tool still running stays in view: a Workflow
    /// or a long build can write nothing to the session's own file for hours.
    static let toolWindow: TimeInterval = 12 * 3_600

    public init(root: URL, redaction: AgentRedaction) {
        self.root = root
        self.redaction = redaction
    }

    /// Takes a new list and reads every session again, so the list covers all of it.
    public func redact(with redaction: AgentRedaction) {
        self.redaction = redaction
        sessions = [:]
    }

    /// Every session whose transcript changed in the last twelve hours, latest first.
    /// One is live while it or a subagent's transcript changed within the live window,
    /// or a tool it started is still running; the rest read as idle.
    public func statuses(now: Date = Date()) -> [AgentStatus] {
        let recent = Self.contents(of: root).flatMap(Self.contents(of:)).filter { url in
            url.pathExtension == "jsonl" && !TranscriptReader.isSubagentTranscript(url.lastPathComponent)
                && Self.age(of: url, at: now) <= Self.toolWindow
        }
        sessions = sessions.filter { recent.contains($0.key) }

        return recent.compactMap { url -> AgentStatus? in
            let subagents = Self.subagentTranscripts(of: url).filter { Self.age(of: $0, at: now) <= TranscriptReader.liveWindow }.count
            readOn(url)
            guard var status = sessions[url]?.transcript.status(now: now) else { return nil }
            status.subagents = subagents
            if subagents > 0, status.activity == .idle {
                status.activity = .tool
                status.verb = "Running \(subagents) agent\(subagents == 1 ? "" : "s")"
            }
            return status
        }
        .sorted { $0.updatedAt > $1.updatedAt }
    }

    /// Reads the whole lines appended since the last read, from the start the first
    /// time, a few megabytes at a time. A line still being written waits for the next read.
    private func readOn(_ url: URL) {
        var (transcript, offset) = sessions[url]
            ?? (Transcript(session: url.deletingPathExtension().lastPathComponent, redaction: redaction), 0)
        guard let file = try? FileHandle(forReadingFrom: url), (try? file.seek(toOffset: offset)) != nil else { return }
        defer { try? file.close() }
        let newline = UInt8(ascii: "\n")
        var carried = Data()
        while let chunk = try? file.read(upToCount: 4 << 20), !chunk.isEmpty {
            let data = carried + chunk
            guard let end = data.lastIndex(of: newline) else {
                carried = data
                continue
            }
            for line in data[..<end].split(separator: newline) {
                transcript.read(String(decoding: line, as: UTF8.self))
            }
            offset += UInt64(end - data.startIndex + 1)
            carried = Data(data[(end + 1)...])
        }
        sessions[url] = (transcript, offset)
    }

    /// The session's subagents' transcripts, a Workflow's included.
    private static func subagentTranscripts(of session: URL) -> [URL] {
        let folder = session.deletingPathExtension().appending(path: "subagents")
        guard let walk = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
        else { return [] }
        return walk.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
    }

    private static func contents(of folder: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
    }

    private static func age(of url: URL, at now: Date) -> TimeInterval {
        guard let modified = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        else { return .infinity }
        return now.timeIntervalSince(modified)
    }
}
