import XCTest
@testable import D4vAgentBar

final class UsageParserTests: XCTestCase {
    let sample = """
    You are currently using your subscription to power your Claude Code usage

    Current session: 8% used · resets Nov 5 at 5:39pm (Europe/Paris)
    Current week (all models): 15% used · resets Nov 9 at 1:59pm (Europe/Paris)
    Current week (Fable): 0% used · resets Nov 9 at 2pm (Europe/Paris)

    What's contributing to your usage?
    Last 24h · 7 requests · 1 session
      54%  Turn off MCP servers you don't use · 25k tokens per request
    """

    func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        return f.date(from: s)!
    }

    func testParsesThreeLimits() {
        let now = date("2026-11-05T12:00:00Z")
        let limits = UsageParser.parse(sample, now: now)
        XCTAssertEqual(limits.map(\.title), ["Session", "Weekly", "Fable"])
        XCTAssertEqual(limits.map(\.usedPercent), [8, 15, 0])
        XCTAssertEqual(limits[0].leftPercent, 92)
        // 5:39pm Paris (UTC+1 in November) = 16:39 UTC
        XCTAssertEqual(limits[0].resetsAt, date("2026-11-05T16:39:00Z"))
        XCTAssertEqual(limits[1].resetsAt, date("2026-11-09T12:59:00Z"))
        XCTAssertEqual(limits[2].resetsAt, date("2026-11-09T13:00:00Z"))
    }

    func testTimeOnlyAndYearRollover() {
        let now = date("2026-12-30T12:00:00Z")
        XCTAssertEqual(UsageParser.parseResetDate("Jan 2 at 9am (UTC)", now: now), date("2027-01-02T09:00:00Z"))
        XCTAssertEqual(UsageParser.parseResetDate("11am (UTC)", now: now), date("2026-12-31T11:00:00Z"))
        XCTAssertEqual(UsageParser.parseResetDate("12:30am (UTC)", now: now), date("2026-12-31T00:30:00Z"))
    }

    func testElapsedAndAge() {
        XCTAssertEqual(AgentMonitor.parseElapsed("05:07"), 307)
        XCTAssertEqual(AgentMonitor.parseElapsed("01:02:03"), 3_723)
        XCTAssertEqual(AgentMonitor.parseElapsed("8-00:00:10"), 8 * 86_400 + 10)
        XCTAssertNil(AgentMonitor.parseElapsed("abc"))
        let now = date("2026-11-05T12:00:00Z")
        XCTAssertEqual(AgentRow.age(since: now.addingTimeInterval(-8 * 86_400 - 5), now: now), "8d")
        XCTAssertEqual(AgentRow.age(since: now.addingTimeInterval(-3 * 3_600), now: now), "3h")
        XCTAssertEqual(AgentRow.age(since: now.addingTimeInterval(-20), now: now), "1m")
    }

    func testCountdown() {
        let now = date("2026-11-05T12:00:00Z")
        XCTAssertEqual(UsageParser.countdown(to: now.addingTimeInterval(4 * 86_400 + 21 * 3_600 + 50), now: now), "4d 21h")
        XCTAssertEqual(UsageParser.countdown(to: now.addingTimeInterval(2 * 3_600 + 47 * 60), now: now), "2h 47m")
        XCTAssertEqual(UsageParser.countdown(to: now.addingTimeInterval(-5), now: now), "now")
    }
}
