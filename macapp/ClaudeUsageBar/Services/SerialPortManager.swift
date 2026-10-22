import Foundation
import Darwin

/// Port of the USB-serial half of `tools/usage_push.py`: finds the ESP's
/// `/dev/cu.usbmodem*` device, configures it (115200 8N1 raw, no echo — the same as
/// `stty -f <port> 115200 raw -echo`), and writes lines to it.
@MainActor
final class SerialPortManager: ObservableObject {
    /// Sentinel stored as the user's preference meaning "pick the first device found".
    static let autoDetect = ""

    @Published private(set) var availablePorts: [String] = []
    @Published private(set) var isConnected: Bool = false
    @Published var selectedPort: String {
        didSet {
            UserDefaults.standard.set(selectedPort, forKey: Self.prefKey)
            refreshPorts()
        }
    }

    private static let prefKey = "serialPortPreference"
    private static let checkInterval: TimeInterval = 30

    private var fd: Int32 = -1
    private var openedPath: String?
    private var openedAt: Date = .distantPast
    private var pollTimer: Timer?

    init() {
        selectedPort = UserDefaults.standard.string(forKey: Self.prefKey) ?? Self.autoDetect
        refreshPorts()
        let t = Timer.scheduledTimer(withTimeInterval: Self.checkInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refreshPorts() }
        }
        t.tolerance = Self.checkInterval * 0.1
        pollTimer = t
    }

    /// Re-scans `/dev` for ESP serial devices and opens/closes the port as needed.
    /// Called every 30s by the timer, and whenever the user changes `selectedPort`.
    func refreshPorts() {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: "/dev")) ?? []
        availablePorts = entries
            .filter { $0.hasPrefix("cu.usbmodem") }
            .map { "/dev/" + $0 }
            .sorted()

        let target = resolveTargetPort()
        if target == openedPath, fd >= 0 {
            isConnected = true
            return
        }
        closePort()
        guard let target else { return }
        openPort(target)
    }

    /// Writes one line (as produced by `SerialLineFormatter`) to the currently open port, if any.
    func send(_ line: String) {
        guard fd >= 0 else { return }
        // Mirror the Python script's `time.sleep(2)` right after opening — the board
        // resets when the port opens, so skip writes until it's had time to come back up.
        guard Date().timeIntervalSince(openedAt) > 2 else { return }

        let bytes = Array(line.utf8)
        let n = bytes.withUnsafeBufferPointer { buf in
            Darwin.write(fd, buf.baseAddress, buf.count)
        }
        if n < 0 {
            closePort()
        }
    }

    private func resolveTargetPort() -> String? {
        if selectedPort != Self.autoDetect {
            return availablePorts.contains(selectedPort) ? selectedPort : nil
        }
        return availablePorts.first
    }

    private func openPort(_ path: String) {
        let newFd = open(path, O_WRONLY | O_NOCTTY)
        guard newFd >= 0 else {
            isConnected = false
            return
        }

        var tty = termios()
        tcgetattr(newFd, &tty)
        cfmakeraw(&tty)
        cfsetspeed(&tty, speed_t(B115200))
        tcsetattr(newFd, TCSANOW, &tty)

        fd = newFd
        openedPath = path
        openedAt = Date()
        isConnected = true
    }

    private func closePort() {
        if fd >= 0 { close(fd) }
        fd = -1
        openedPath = nil
        isConnected = false
    }

    deinit {
        pollTimer?.invalidate()
        if fd >= 0 { close(fd) }
    }
}
