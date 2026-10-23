import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: UsageStore
    @EnvironmentObject var serial: SerialPortManager
    @AppStorage("dashboardStyle") private var styleRaw: String = DashboardStyle.synthwave.rawValue

    var body: some View {
        Form {
            Picker("Style", selection: $styleRaw) {
                ForEach(DashboardStyle.allCases) { style in
                    Text(style.rawValue).tag(style.rawValue)
                }
            }
            .pickerStyle(.menu)

            Stepper(value: $store.refreshInterval, in: 10...300, step: 10) {
                Text("Refresh every \(Int(store.refreshInterval))s")
            }

            Divider()

            Picker("USB device", selection: $serial.selectedPort) {
                Text("Auto-detect").tag(SerialPortManager.autoDetect)
                ForEach(serial.availablePorts, id: \.self) { port in
                    Text((port as NSString).lastPathComponent).tag(port)
                }
            }

            HStack {
                Circle()
                    .fill(serial.isConnected ? Color.green : Color.secondary)
                    .frame(width: 8, height: 8)
                Text(serial.isConnected ? "Connected" : "No device connected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Rescan") {
                    serial.refreshPorts()
                }
                .font(.caption)
            }
        }
        .padding()
        .frame(width: 380)
    }
}
