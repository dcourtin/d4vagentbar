import Foundation

/// Lists running Claude Code CLI processes (binary named `claude`) and their working folder.
@MainActor
final class AgentMonitor: ObservableObject {
    struct Agent: Identifiable, Equatable {
        let id: Int32       // pid
        let folder: String? // working directory
        var name: String { folder.map { ($0 as NSString).lastPathComponent } ?? "pid \(id)" }
    }

    @Published private(set) var agents: [Agent] = []
    private var timer: Timer?

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
        agents = names.enumerated().map { Agent(id: Int32($0.offset + 1), folder: "/demo/\($0.element)") }
    }

    private var demo = false

    func refresh() {
        guard !demo else { return }
        Task.detached {
            let found = Self.scan()
            await MainActor.run { if !self.demo, found != self.agents { self.agents = found } }
        }
    }

    nonisolated static func scan() -> [Agent] {
        guard let ps = try? ClaudeCLI.run(URL(fileURLWithPath: "/bin/ps"), ["-axo", "pid=,ppid=,comm="]) else { return [] }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let pids: [Int32] = ps.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3, let pid = Int32(fields[0]), let ppid = Int32(fields[1]) else { return nil }
            // Skip the `claude -p /usage` this app launches itself.
            guard ppid != ownPID else { return nil }
            // Case-sensitive: the desktop app itself is "Claude".
            return (String(fields[2]) as NSString).lastPathComponent == "claude" ? pid : nil
        }
        // `claude -p /usage` runs in the temp folder (see ClaudeCLI.run): not an agent.
        let tmp = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL.path
        return pids.map { Agent(id: $0, folder: workingDirectory(of: $0)) }
            .filter { agent in
                guard let folder = agent.folder else { return true }
                return URL(fileURLWithPath: folder).resolvingSymlinksInPath().standardizedFileURL.path != tmp
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    nonisolated static func workingDirectory(of pid: Int32) -> String? {
        guard let out = try? ClaudeCLI.run(URL(fileURLWithPath: "/usr/sbin/lsof"),
                                           ["-a", "-p", "\(pid)", "-d", "cwd", "-Fn"]) else { return nil }
        return out.split(separator: "\n").first { $0.hasPrefix("n") }.map { String($0.dropFirst()) }
    }
}
