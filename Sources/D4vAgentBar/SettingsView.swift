import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var usage: UsageStore
    @EnvironmentObject private var keepAwake: KeepAwake
    @AppStorage("showPercentInMenuBar") private var showPercent = true
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section("Menu bar") {
                Toggle("Show session % left in the menu bar", isOn: $showPercent)
                Picker("Refresh usage every", selection: $usage.refreshMinutes) {
                    Text("1 minute").tag(1.0)
                    Text("2 minutes").tag(2.0)
                    Text("5 minutes").tag(5.0)
                    Text("10 minutes").tag(10.0)
                    Text("15 minutes").tag(15.0)
                }
            }
            Section("Keep Awake") {
                Toggle("Keep the display on too", isOn: $keepAwake.keepDisplayOn)
            }
            Section("General") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        do {
                            if enabled { try SMAppService.mainApp.register() }
                            else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                LabeledContent("claude CLI", value: ClaudeCLI.executableURL?.path ?? "not found")
                if let updated = usage.lastUpdated {
                    LabeledContent("Last update", value: updated.formatted(date: .omitted, time: .shortened))
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize()
    }
}
