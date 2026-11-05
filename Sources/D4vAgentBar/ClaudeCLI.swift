import Foundation

/// Runs the local `claude` CLI. A menu bar app does not inherit the shell PATH,
/// so the binary is looked up in the usual install locations first.
enum ClaudeCLI {
    enum CLIError: LocalizedError {
        case notFound
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notFound: return "claude CLI not found"
            case .failed(let message): return message
            }
        }
    }

    static let executableURL: URL? = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
        ]
        if let path = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: path)
        }
        // Fall back to the user's login shell PATH.
        if let output = try? run(URL(fileURLWithPath: "/bin/zsh"), ["-lc", "command -v claude"]),
           let path = output.split(separator: "\n").last.map(String.init),
           FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }
        return nil
    }()

    /// Text of `claude -p "/usage"`. Local command: no model call, no quota used.
    static func usageText() throws -> String {
        guard let claude = executableURL else { throw CLIError.notFound }
        let output = try run(claude, ["-p", "/usage", "--output-format", "json", "--no-session-persistence"])
        struct Result: Decodable { let result: String?; let is_error: Bool? }
        if let data = output.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(Result.self, from: data),
           let text = decoded.result {
            if decoded.is_error == true { throw CLIError.failed(text) }
            return text
        }
        return output
    }

    /// Subscription type from `claude auth status` ("max", "pro"…).
    static func subscriptionType() -> String? {
        guard let claude = executableURL,
              let output = try? run(claude, ["auth", "status"]),
              let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["subscriptionType"] as? String
    }

    @discardableResult
    static func run(_ executable: URL, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        // Neutral folder so the CLI does not pick up a project's settings or hooks.
        process.currentDirectoryURL = FileManager.default.temporaryDirectory

        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        env["PATH"] = ["\(home)/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", env["PATH"] ?? ""]
            .joined(separator: ":")
        env["NO_COLOR"] = "1"
        process.environment = env

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        process.standardInput = FileHandle.nullDevice

        try process.run()
        let outData = stdout.fileHandleForReading.readDataToEndOfFile()
        let errData = stderr.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        let out = String(decoding: outData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            let err = String(decoding: errData, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
            throw CLIError.failed(err.isEmpty ? out : err)
        }
        return out
    }
}
