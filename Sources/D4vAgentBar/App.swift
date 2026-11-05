import AppKit
import SwiftUI

@main
struct D4vAgentBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var usage = UsageStore()
    @StateObject private var keepAwake = KeepAwake()
    @StateObject private var agents = AgentMonitor()
    @AppStorage("showPercentInMenuBar") private var showPercent = true

    var body: some Scene {
        MenuBarExtra {
            MenuContentView()
                .environmentObject(usage)
                .environmentObject(keepAwake)
                .environmentObject(agents)
        } label: {
            MenuBarLabel(session: usage.session, showPercent: showPercent, awake: keepAwake.isActive)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(usage)
                .environmentObject(keepAwake)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon, also when launched with `swift run` (outside an .app bundle).
        NSApp.setActivationPolicy(.accessory)

        // Debug: `d4vAgentBar --snapshot out.png` renders the menu to a PNG and quits.
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
            let demo = args.contains("--demo")
            Task { @MainActor in await Self.snapshot(to: URL(fileURLWithPath: args[i + 1]), demo: demo) }
        }
    }

    @MainActor
    private static func snapshot(to url: URL, demo: Bool) async {
        let usage = UsageStore()
        let agents = AgentMonitor()
        if demo { agents.useDemoAgents(["api-server", "website"]) }
        await usage.refresh()
        try? await Task.sleep(for: .seconds(2))
        let view = MenuContentView()
            .environmentObject(usage)
            .environmentObject(KeepAwake())
            .environmentObject(agents)
            .background(Color(nsColor: .windowBackgroundColor))
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        if let image = renderer.nsImage,
           let tiff = image.tiffRepresentation,
           let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
        NSApp.terminate(nil)
    }
}

struct MenuBarLabel: View {
    let session: UsageLimit?
    let showPercent: Bool
    let awake: Bool

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: awake ? "sun.max.fill" : "asterisk")
            if showPercent, let session {
                Text("\(Int(session.leftPercent.rounded()))%")
                    .monospacedDigit()
            }
        }
    }
}
