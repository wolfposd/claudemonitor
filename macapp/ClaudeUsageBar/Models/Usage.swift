import Foundation

/// Mirrors the `Usage` struct the ESP firmware parses from the `U,...` serial line,
/// and the fields `tools/usage_push.py`'s `collect()` computes.
struct Usage: Equatable {
    var weekday: Int = 0       // 0 = Monday
    var day: [Int] = Array(repeating: 0, count: 7)   // oldest..today, day[6] == today
    var h5: Int = 0            // tokens in the last 5 hours
    var msgs: Int = 0          // messages sent today

    var pct5: Int?             // session (5h) limit utilization %, nil == unknown
    var reset5Min: Int?        // minutes until session limit resets
    var pct7: Int?             // weekly (7d) limit utilization %, nil == unknown
    var reset7Min: Int?        // minutes until weekly limit resets

    var lastUpdated: Date = .distantPast

    static let empty = Usage()

    var isValid: Bool { lastUpdated != .distantPast }

    var ageSeconds: TimeInterval { Date().timeIntervalSince(lastUpdated) }
    var isStale: Bool { isValid && ageSeconds > 180 }

    var today: Int { day[6] }

    var sevenDayTotal: Int { day.reduce(0, +) }
}
