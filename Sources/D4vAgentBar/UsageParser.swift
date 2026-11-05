import Foundation

/// One quota line from `claude -p "/usage"`, e.g.
/// `Current week (all models): 15% used · resets Nov 9 at 1:59pm (Europe/Paris)`.
struct UsageLimit: Identifiable, Equatable {
    var id: String { title }
    let title: String        // "Session", "Weekly", "Fable"…
    let usedPercent: Double  // 0…100
    let resetsAt: Date?
    let resetsText: String?  // raw text, shown when the date could not be parsed

    var leftPercent: Double { max(0, min(100, 100 - usedPercent)) }
}

enum UsageParser {
    /// Parses the human-readable text printed by `/usage`.
    static func parse(_ text: String, now: Date = Date()) -> [UsageLimit] {
        let lineRegex = try! NSRegularExpression(
            pattern: #"^\s*(.+?):\s*(\d+(?:\.\d+)?)%\s*used(?:\s*·\s*resets\s+(.+?))?\s*$"#,
            options: [.caseInsensitive]
        )
        var limits: [UsageLimit] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine as NSString
            guard let m = lineRegex.firstMatch(in: rawLine, range: NSRange(location: 0, length: line.length)) else { continue }
            let label = line.substring(with: m.range(at: 1))
            let used = Double(line.substring(with: m.range(at: 2))) ?? 0
            let resets = m.range(at: 3).location != NSNotFound ? line.substring(with: m.range(at: 3)) : nil
            limits.append(UsageLimit(
                title: displayTitle(for: label),
                usedPercent: used,
                resetsAt: resets.flatMap { parseResetDate($0, now: now) },
                resetsText: resets
            ))
        }
        return limits
    }

    /// "Current session" → "Session", "Current week (all models)" → "Weekly",
    /// "Current week (Fable)" → "Fable".
    static func displayTitle(for label: String) -> String {
        let lower = label.lowercased()
        if lower.contains("session") { return "Session" }
        if let open = label.firstIndex(of: "("), let close = label.lastIndex(of: ")"), open < close {
            let inner = String(label[label.index(after: open)..<close]).trimmingCharacters(in: .whitespaces)
            if inner.lowercased() == "all models" { return "Weekly" }
            return inner
        }
        if lower.contains("week") { return "Weekly" }
        return label.replacingOccurrences(of: "Current ", with: "").capitalized
    }

    /// Parses "Nov 9 at 1:59pm (Europe/Paris)", "Nov 9 at 2pm (Europe/Paris)" or "5:39pm (Europe/Paris)".
    static func parseResetDate(_ text: String, now: Date = Date()) -> Date? {
        let regex = try! NSRegularExpression(
            pattern: #"^(?:([A-Za-z]{3})[a-z]*\.?\s+(\d{1,2})(?:,\s*(\d{4}))?\s+at\s+)?(\d{1,2})(?::(\d{2}))?\s*(am|pm)?\s*(?:\(([^)]+)\))?"#,
            options: [.caseInsensitive]
        )
        let ns = text.trimmingCharacters(in: .whitespaces) as NSString
        guard let m = regex.firstMatch(in: ns as String, range: NSRange(location: 0, length: ns.length)) else { return nil }
        func group(_ i: Int) -> String? {
            m.range(at: i).location == NSNotFound ? nil : ns.substring(with: m.range(at: i))
        }

        let tz = group(7).flatMap { TimeZone(identifier: $0) } ?? .current
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = tz

        guard var hour = group(4).flatMap(Int.init) else { return nil }
        let minute = group(5).flatMap(Int.init) ?? 0
        if let ampm = group(6)?.lowercased() {
            if ampm == "pm", hour < 12 { hour += 12 }
            if ampm == "am", hour == 12 { hour = 0 }
        }

        var comps = cal.dateComponents([.year, .month, .day], from: now)
        comps.hour = hour
        comps.minute = minute
        comps.second = 0

        let hasDate = group(1) != nil
        if hasDate {
            let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]
            guard let monthIndex = months.firstIndex(of: group(1)!.lowercased()),
                  let day = group(2).flatMap(Int.init) else { return nil }
            comps.month = monthIndex + 1
            comps.day = day
            if let year = group(3).flatMap(Int.init) { comps.year = year }
        }

        guard var date = cal.date(from: comps) else { return nil }
        if hasDate, group(3) == nil, date < now.addingTimeInterval(-86_400) {
            // "Jan 2" seen in late December belongs to next year.
            date = cal.date(byAdding: .year, value: 1, to: date) ?? date
        } else if !hasDate, date < now {
            date = cal.date(byAdding: .day, value: 1, to: date) ?? date
        }
        return date
    }

    /// "4d 21h", "2h 47m", "12m", "now".
    static func countdown(to date: Date, now: Date = Date()) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        if seconds <= 0 { return "now" }
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        return "\(max(minutes, 1))m"
    }
}
