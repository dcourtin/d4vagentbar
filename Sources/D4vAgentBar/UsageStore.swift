import Foundation
import SwiftUI

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var limits: [UsageLimit] = []
    @Published private(set) var plan: String?
    @Published private(set) var lastUpdated: Date?
    @Published private(set) var error: String?
    @Published private(set) var isLoading = false

    @Published var refreshMinutes: Double = UserDefaults.standard.object(forKey: "refreshMinutes") as? Double ?? 5 {
        didSet {
            UserDefaults.standard.set(refreshMinutes, forKey: "refreshMinutes")
            scheduleTimer()
        }
    }

    private var timer: Timer?

    init() {
        scheduleTimer()
        Task { await refresh() }
        Task.detached {
            let plan = ClaudeCLI.subscriptionType()
            await MainActor.run { self.plan = plan.map { $0.prefix(1).uppercased() + $0.dropFirst() } }
        }
    }

    var session: UsageLimit? { limits.first { $0.title == "Session" } }

    /// Called when the menu opens: refresh unless the data is very recent.
    func refreshIfStale() {
        guard let lastUpdated, Date().timeIntervalSince(lastUpdated) < 30 else {
            Task { await refresh() }
            return
        }
    }

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let text = try await Task.detached { try ClaudeCLI.usageText() }.value
            let parsed = UsageParser.parse(text)
            if parsed.isEmpty {
                error = "Unrecognised /usage output"
            } else {
                limits = parsed
                error = nil
                lastUpdated = Date()
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let interval = max(1, refreshMinutes) * 60
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            Task { await self?.refresh() }
        }
    }
}
