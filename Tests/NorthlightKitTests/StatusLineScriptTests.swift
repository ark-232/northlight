import Foundation
import Testing

/// Runs scripts/northlight-statusline.sh with `stdin`, then `command`, writing into a
/// fresh folder. Returns what the command printed and the usage file, if one was written.
private func run(_ stdin: String, command: [String] = ["cat"]) throws -> (output: String, usage: [String: Any]?, files: [String]) {
    let script = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appending(path: "scripts/northlight-statusline.sh")
    let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: folder) }
    let process = Process()
    process.executableURL = URL(filePath: "/bin/sh")
    process.arguments = [script.path] + command
    process.environment = ["NORTHLIGHT_USAGE_DIR": folder.path, "PATH": "/usr/bin:/bin"]
    let input = Pipe(), output = Pipe()
    process.standardInput = input
    process.standardOutput = output
    try process.run()
    input.fileHandleForWriting.write(Data(stdin.utf8))
    try input.fileHandleForWriting.close()
    let printed = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    #expect(process.terminationStatus == 0)
    let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    let usage = (try? Data(contentsOf: folder.appending(path: "usage.json")))
        .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    return (String(decoding: printed, as: UTF8.self), usage, files)
}

struct StatusLineScriptTests {
    private let both = """
        {"cwd":"/Users/me/rate_limits","session_name":"secret","transcript_path":"/t.jsonl",\
        "rate_limits":{"five_hour":{"used_percentage":42.5,"resets_at":1760900000},\
        "seven_day":{"used_percentage":18,"resets_at":1761200000}}}

        """

    /// The status line the person already has sees the same bytes, trailing newline and all.
    @Test func theCommandGetsStdinUnchanged() throws {
        #expect(try run(both).output == both)
    }

    @Test func onlyTheTwoWindowsAndTheTimeAreSaved() throws {
        let usage = try #require(try run(both).usage)
        #expect(Set(usage.keys) == ["five_hour", "seven_day", "observed_at"])
        let five = try #require(usage["five_hour"] as? [String: Double])
        #expect(five == ["used_percentage": 42.5, "resets_at": 1_760_900_000])
        let observed = try #require(usage["observed_at"] as? Double)
        #expect(abs(observed - Date().timeIntervalSince1970) < 60)
    }

    /// The word in a path or a session name is not usage.
    @Test func nothingIsWrittenWithoutRateLimits() throws {
        let result = try run(#"{"cwd":"/rate_limits","session_name":"\"rate_limits\""}"#)
        #expect(result.output == #"{"cwd":"/rate_limits","session_name":"\"rate_limits\""}"#)
        #expect(result.files.isEmpty)
    }

    @Test func aMissingWindowIsLeftOut() throws {
        let usage = try #require(try run(#"{"rate_limits":{"seven_day":{"used_percentage":3,"resets_at":1761200000}}}"#).usage)
        #expect(Set(usage.keys) == ["seven_day", "observed_at"])
    }

    @Test func textInPlaceOfANumberIsNotSaved() throws {
        let result = try run(#"{"rate_limits":{"five_hour":{"used_percentage":"1}, \"x\":{","resets_at":1}}}"#)
        #expect(result.files.isEmpty)
    }

    @Test func notJSONStillReachesTheCommand() throws {
        let result = try run("rate_limits\n")
        #expect(result.output == "rate_limits\n")
        #expect(result.files.isEmpty)
    }

    @Test func theCommandKeepsItsArguments() throws {
        #expect(try run("{}", command: ["printf", "%s|%s", "a b", "--style=powerline"]).output == "a b|--style=powerline")
    }
}
