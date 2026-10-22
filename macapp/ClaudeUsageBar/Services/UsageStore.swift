import Foundation
import Combine

@MainActor
final class UsageStore: ObservableObject {
    @Published private(set) var usage: Usage = .empty
    @Published private(set) var lastError: String?
    @Published var refreshInterval: TimeInterval = 30 {
        didSet { scheduleTimer() }
    }

    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private let serial: SerialPortManager

    init(serial: SerialPortManager) {
        self.serial = serial
        refresh()
        scheduleTimer()
    }

    private func scheduleTimer() {
        timer?.invalidate()
        let t = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.refresh()
        }
        // Let the system coalesce this wakeup with other timers instead of
        // waking the CPU at the exact instant every time.
        t.tolerance = refreshInterval * 0.1
        timer = t
    }

    func refresh() {
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            guard let self else { return }
            async let collected = UsageCollector.collect()
            async let limits = KeychainUsageClient.fetchLimits()
            var u = await collected
            let lim = await limits
            u.pct5 = lim.pct5
            u.reset5Min = lim.reset5Min
            u.pct7 = lim.pct7
            u.reset7Min = lim.reset7Min
            self.usage = u
            self.lastError = lim.error
            self.serial.send(SerialLineFormatter.line(for: u))
        }
    }

    deinit {
        timer?.invalidate()
    }
}
