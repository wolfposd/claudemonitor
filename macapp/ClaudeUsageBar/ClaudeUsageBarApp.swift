import SwiftUI

@main
struct ClaudeUsageBarApp: App {
    @StateObject private var serial: SerialPortManager
    @StateObject private var store: UsageStore

    init() {
        // No Dock icon / app switcher entry (equivalent to LSUIElement), set programmatically
        // so the app runs as a plain unsandboxed executable without needing an Info.plist bundle step.
        NSApplication.shared.setActivationPolicy(.accessory)

        let serial = SerialPortManager()
        _serial = StateObject(wrappedValue: serial)
        _store = StateObject(wrappedValue: UsageStore(serial: serial))
    }

    var body: some Scene {
        MenuBarExtra {
            DashboardPanelView()
                .environmentObject(store)
                .environmentObject(serial)
        } label: {
            MenuBarIconView(usage: store.usage)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(store)
                .environmentObject(serial)
        }
    }
}
