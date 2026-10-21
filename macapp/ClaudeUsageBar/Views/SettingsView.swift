import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: UsageStore
    @AppStorage("dashboardStyle") private var styleRaw: String = DashboardStyle.synthwave.rawValue

    var body: some View {
        Form {
            Picker("Style", selection: $styleRaw) {
                ForEach(DashboardStyle.allCases) { style in
                    Text(style.rawValue).tag(style.rawValue)
                }
            }
            .pickerStyle(.segmented)

            Stepper(value: $store.refreshInterval, in: 10...300, step: 10) {
                Text("Refresh every \(Int(store.refreshInterval))s")
            }
        }
        .padding()
        .frame(width: 260)
    }
}
