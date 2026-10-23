import Foundation

/// Port of the firmware's `fmtTokens()` — compact human-readable token counts.
enum TokenFormatting {
    static func format(_ v: Int) -> String {
        switch v {
        case 1_000_000...:
            return String(format: "%d.%dM", v / 1_000_000, (v % 1_000_000) / 100_000)
        case 10_000..<1_000_000:
            return "\(v / 1000)K"
        case 1_000..<10_000:
            return String(format: "%d.%dK", v / 1000, (v % 1000) / 100)
        default:
            return "\(v)"
        }
    }

    /// Compact USD display for an estimated cost, e.g. "$0.004" or "$1.23".
    static func formatCost(_ v: Double) -> String {
        v < 0.01 ? String(format: "$%.4f", v) : String(format: "$%.2f", v)
    }
}
