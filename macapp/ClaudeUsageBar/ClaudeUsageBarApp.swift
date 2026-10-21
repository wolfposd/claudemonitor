import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @StateObject private var store = UsageStore()

    init() {
        // No Dock icon / app switcher entry (equivalent to LSUIElement), set programmatically
        // so the app runs as a plain unsandboxed executable without needing an Info.plist bundle step.
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardPanelView()
                .environmentObject(store)
        } label: {
            MenuBarIconView(usage: store.usage)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
