import Foundation
import IOKit.pwr_mgt

/// Prevents sleep with an IOKit power assertion (what `caffeinate` does).
@MainActor
final class KeepAwake: ObservableObject {
    @Published private(set) var isActive = false
    /// nil while active means "indefinitely".
    @Published private(set) var until: Date?

    @Published var keepDisplayOn: Bool = UserDefaults.standard.object(forKey: "keepDisplayOn") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(keepDisplayOn, forKey: "keepDisplayOn")
            if isActive { start(until: until) }  // re-create with the new assertion type
        }
    }

    private var assertionID: IOPMAssertionID = 0
    private var timer: Timer?

    static let durations: [(label: String, seconds: TimeInterval?)] = [
        ("15 minutes", 15 * 60),
        ("30 minutes", 30 * 60),
        ("1 hour", 3_600),
        ("2 hours", 2 * 3_600),
        ("4 hours", 4 * 3_600),
        ("8 hours", 8 * 3_600),
        ("Indefinitely", nil),
    ]

    func start(for seconds: TimeInterval?) {
        start(until: seconds.map { Date().addingTimeInterval($0) })
    }

    private func start(until end: Date?) {
        releaseAssertion()
        let type = (keepDisplayOn ? kIOPMAssertionTypeNoDisplaySleep : kIOPMAssertionTypeNoIdleSleep) as CFString
        let result = IOPMAssertionCreateWithName(type, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                                 "d4vAgentBar: Keep Awake" as CFString, &assertionID)
        guard result == kIOReturnSuccess else { return }
        isActive = true
        until = end
        timer?.invalidate()
        if let end {
            timer = Timer.scheduledTimer(withTimeInterval: max(1, end.timeIntervalSinceNow), repeats: false) { [weak self] _ in
                Task { @MainActor in self?.stop() }
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        releaseAssertion()
        isActive = false
        until = nil
    }

    private func releaseAssertion() {
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
    }
}
