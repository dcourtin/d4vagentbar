import Darwin
import Foundation

/// Lists running Claude Code CLI processes (binary named `claude`) and their working folder.
@MainActor
final class AgentMonitor: ObservableObject {
    struct Agent: Identifiable, Equatable {
        let id: Int32         // pid
        let folder: String?   // working directory
        let startedAt: Date?
        /// Session run by the Claude desktop app: stop it from the app, not from here.
        let isDesktopApp: Bool
        var name: String { folder.map { ($0 as NSString).lastPathComponent } ?? "pid \(id)" }
    }

    @Published private(set) var agents: [Agent] = []
    private var timer: Timer?
    private var demo = false

    init() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    /// Fixed sample list for screenshots (`--snapshot … --demo`).
    func useDemoAgents(_ names: [String]) {
        timer?.invalidate()
        demo = true
        agents = names.enumerated().map {
            Agent(id: Int32($0.offset + 1), folder: "/demo/\($0.element)",
                  startedAt: Date().addingTimeInterval(-Double($0.offset + 1) * 5_400), isDesktopApp: false)
        }
    }

    func refresh() {
        guard !demo else { return }
        Task.detached {
            let found = Self.scan()
            await MainActor.run { if !self.demo, found != self.agents { self.agents = found } }
        }
    }

    /// Asks the session to quit (SIGTERM, like `kill <pid>`): Claude Code exits cleanly
    /// and the conversation stays available with `claude --resume`.
    func stop(_ agent: Agent) {
        guard !agent.isDesktopApp else { return }
        if demo {
            agents.removeAll { $0.id == agent.id }
            return
        }
        kill(agent.id, SIGTERM)
        agents.removeAll { $0.id == agent.id }
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            refresh()
        }
    }

    nonisolated static func scan() -> [Agent] {
        guard let ps = try? ClaudeCLI.run(URL(fileURLWithPath: "/bin/ps"), ["-axo", "pid=,ppid=,etime=,comm="]) else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let now = Date()
        let found: [(pid: Int32, startedAt: Date?, desktop: Bool)] = ps.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
            guard fields.count == 4, let pid = Int32(fields[0]), let ppid = Int32(fields[1]) else { return nil }
            // Skip the `claude -p /usage` this app launches itself.
            guard ppid != ownPID else { return nil }
            let command = String(fields[3])
            // Case-sensitive: the desktop app itself is "Claude".
            guard (command as NSString).lastPathComponent == "claude" else { return nil }
            let started = parseElapsed(String(fields[2])).map { now.addingTimeInterval(-$0) }
            // The desktop app runs its own copy of Claude Code from Application Support.
            let desktop = command.contains("/Application Support/Claude/")
            return (pid, started, desktop)
        }
        // `claude -p /usage` runs in the temp folder (see ClaudeCLI.run): not an agent.
        let tmp = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        return found.map { Agent(id: $0.pid, folder: workingDirectory(of: $0.pid), startedAt: $0.startedAt, isDesktopApp: $0.desktop) }
            .filter { agent in
                guard let folder = agent.folder else { return true }
                return URL(fileURLWithPath: folder).resolvingSymlinksInPath().standardizedFileURL.path != tmp
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Parses `ps` elapsed time: `[[dd-]hh:]mm:ss`.
    nonisolated static func parseElapsed(_ text: String) -> TimeInterval? {
        var days = 0.0
        var rest = Substring(text)
        if let dash = rest.firstIndex(of: "-") {
            guard let d = Double(rest[..<dash]) else { return nil }
            days = d
            rest = rest[rest.index(after: dash)...]
        }
        let parts = rest.split(separator: ":").map { Double($0) }
        guard !parts.isEmpty, parts.count <= 3, parts.allSatisfy({ $0 != nil }) else { return nil }
        let seconds = parts.reduce(0.0) { $0 * 60 + $1! }
        return days * 86_400 + seconds
    }

    nonisolated static func workingDirectory(of pid: Int32) -> String? {
        guard let out = try? ClaudeCLI.run(URL(fileURLWithPath: "/usr/sbin/lsof"),
                                           ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]) else { return nil }
        return out.split(separator: "\n").first { $0.hasPrefix("n") }.map { String($0.dropFirst()) }
    }
}
