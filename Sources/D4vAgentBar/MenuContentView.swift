import AppKit
import SwiftUI

struct MenuContentView: View {
    @EnvironmentObject private var usage: UsageStore
    @EnvironmentObject private var keepAwake: KeepAwake
    @EnvironmentObject private var agents: AgentMonitor
    @Environment(\.openSettings) private var openSettings
    @AppStorage("claudeSectionExpanded") private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            keepAwakeSection
            divider
            claudeSection
            divider
            agentsSection
            divider
            MenuRow(title: "Menubar Settings…", shortcut: "⌘ ,") {
                NSApp.activate(ignoringOtherApps: true)
                openSettings()
            }
            .keyboardShortcut(",", modifiers: .command)
            divider
            MenuRow(title: "Quit d4vAgentBar", shortcut: "⌘ Q") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .frame(width: 320)
        .onAppear {
            usage.refreshIfStale()
            agents.refresh()
        }
    }

    private var divider: some View {
        Divider().padding(.horizontal, 10).padding(.vertical, 6)
    }

    // MARK: Keep awake

    private var keepAwakeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Menu {
                ForEach(KeepAwake.durations, id: \.label) { option in
                    Button(option.label) { keepAwake.start(for: option.seconds) }
                }
                if keepAwake.isActive {
                    Divider()
                    Button("Turn Off") { keepAwake.stop() }
                }
            } label: {
                MenuRowLabel(title: "Keep Awake For", trailing: keepAwakeStatus, chevron: true)
            }
            .menuStyle(.button)
            .buttonStyle(MenuRowButtonStyle())
            .menuIndicator(.hidden)

            Menu {
                Toggle("Keep Display On", isOn: $keepAwake.keepDisplayOn)
            } label: {
                MenuRowLabel(title: "Keep Awake Settings", chevron: true)
            }
            .menuStyle(.button)
            .buttonStyle(MenuRowButtonStyle())
            .menuIndicator(.hidden)
        }
    }

    private var keepAwakeStatus: String? {
        guard keepAwake.isActive else { return nil }
        guard let until = keepAwake.until else { return "On" }
        return UsageParser.countdown(to: until)
    }

    // MARK: Claude Code

    private var claudeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "asterisk")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color(red: 0.85, green: 0.47, blue: 0.34))
                    Text("Claude Code").font(.system(size: 14, weight: .bold))
                    if let plan = usage.plan {
                        Text(plan).font(.system(size: 13)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if usage.isLoading {
                        ProgressView().controlSize(.mini)
                    }
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded {
                card
            }
        }
    }

    @ViewBuilder
    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            if usage.limits.isEmpty {
                Text(usage.error ?? "Loading usage…")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(usage.limits) { limit in
                            LimitView(limit: limit, now: context.date)
                        }
                    }
                }
                if let error = usage.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.06)))
        .padding(.horizontal, 4)
        .contextMenu {
            Button("Refresh Now") { Task { await usage.refresh() } }
        }
    }

    // MARK: Agents

    @ViewBuilder
    private var agentsSection: some View {
        if agents.agents.isEmpty {
            Text("No agents running")
                .font(.system(size: 13))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 3)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Text(agents.agents.count == 1 ? "1 agent running" : "\(agents.agents.count) agents running")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                ForEach(agents.agents) { agent in
                    AgentRow(agent: agent) { agents.stop(agent) }
                }
            }
        }
    }
}

/// One running session: folder name and age; on hover, a ✕ that stops it.
/// Desktop-app sessions get no ✕: they are stopped from the Claude app.
struct AgentRow: View {
    let agent: AgentMonitor.Agent
    let onStop: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(.green).frame(width: 6, height: 6)
            Text(agent.name).font(.system(size: 13)).lineLimit(1)
            if agent.isDesktopApp {
                Text("app").font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            Spacer()
            if hovering, !agent.isDesktopApp {
                Button(action: onStop) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Stop this session (kill \(agent.id))")
            } else if let started = agent.startedAt {
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(Self.age(since: started, now: context.date))
                        .font(.system(size: 12))
                        .foregroundStyle(context.date.timeIntervalSince(started) > 86_400 ? Color.orange : Color.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(agent.folder ?? "")
    }

    /// "8d", "3h", "12m".
    static func age(since date: Date, now: Date) -> String {
        let s = max(0, Int(now.timeIntervalSince(date)))
        if s >= 86_400 { return "\(s / 86_400)d" }
        if s >= 3_600 { return "\(s / 3_600)h" }
        return "\(max(1, s / 60))m"
    }
}

struct LimitView: View {
    let limit: UsageLimit
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(limit.title).font(.system(size: 13, weight: .semibold))
            UsageBar(fraction: limit.leftPercent / 100, color: color)
            HStack {
                Text("\(Int(limit.leftPercent.rounded()))% left")
                Spacer()
                Text(resetText).foregroundStyle(.secondary)
            }
            .font(.system(size: 12))
            .monospacedDigit()
        }
    }

    private var resetText: String {
        if let date = limit.resetsAt { return "Resets in \(UsageParser.countdown(to: date, now: now))" }
        if let raw = limit.resetsText { return "Resets \(raw)" }
        return ""
    }

    private var color: Color {
        switch limit.leftPercent {
        case ..<10: return .red
        case ..<25: return .orange
        default: return .accentColor
        }
    }
}

struct UsageBar: View {
    let fraction: Double
    let color: Color

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.15))
                Capsule().fill(color)
                    .frame(width: max(0, min(1, fraction)) * geo.size.width)
            }
        }
        .frame(height: 6)
        .animation(.easeOut(duration: 0.3), value: fraction)
    }
}

// MARK: Menu-like rows

struct MenuRowLabel: View {
    let title: String
    var trailing: String? = nil
    var chevron = false

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13))
            Spacer()
            if let trailing {
                Text(trailing).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
            }
            if chevron {
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold))
            }
        }
    }
}

struct MenuRow: View {
    let title: String
    var shortcut: String? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.system(size: 13))
                Spacer()
                if let shortcut {
                    Text(shortcut).font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
        }
        .buttonStyle(MenuRowButtonStyle())
    }
}

/// Native-menu look: full-width row, accent highlight on hover.
struct MenuRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        HoverRow(configuration: configuration)
    }

    private struct HoverRow: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(hovering ? Color.white : Color.primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hovering ? Color.accentColor.opacity(configuration.isPressed ? 0.8 : 1) : .clear)
                )
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}
