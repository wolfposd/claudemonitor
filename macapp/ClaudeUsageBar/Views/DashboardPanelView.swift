import SwiftUI

enum DashboardStyle: String, CaseIterable, Identifiable {
    case synthwave = "Synthwave"
    case native = "Native"
    var id: String { rawValue }
}

struct DashboardPanelView: View {
    @EnvironmentObject var store: UsageStore
    @AppStorage("dashboardStyle") private var styleRaw: String = DashboardStyle.synthwave.rawValue
    @State private var showSettings = false

    private var style: DashboardStyle {
        DashboardStyle(rawValue: styleRaw) ?? .synthwave
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch style {
                case .synthwave:
                    SynthwaveView(usage: store.usage)
                case .native:
                    NativeDashboardView(usage: store.usage, lastError: store.lastError)
                }
            }

            Divider()

            HStack {
                Button {
                    store.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderless)

                Spacer()

                Button {
                    showSettings.toggle()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.borderless)

                Button {
                    NSApplication.shared.terminate(nil)
                } label: {
                    Label("Quit", systemImage: "power")
                }
                .buttonStyle(.borderless)
            }
            .padding(8)
        }
        .frame(width: style == .synthwave ? 472 : 300)
        .popover(isPresented: $showSettings) {
            SettingsView()
                .environmentObject(store)
        }
    }
}
