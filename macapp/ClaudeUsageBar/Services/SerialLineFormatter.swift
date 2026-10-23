import Foundation

/// Port of `tools/usage_push.py`'s `collect()` output line format:
/// `U,<weekday>,<d0..d6>,<h5>,<msgs>,<pct5>,<reset5>,<pct7>,<reset7>,<h5 cents>,<today cents>,<week cents>\n`
/// (-1 == unknown for limits; costs are USD cents).
enum SerialLineFormatter {
    static func line(for usage: Usage) -> String {
        let days = usage.day.map(String.init).joined(separator: ",")
        let limits = [usage.pct5, usage.reset5Min, usage.pct7, usage.reset7Min]
            .map { $0.map(String.init) ?? "-1" }
            .joined(separator: ",")
        let costs = [usage.h5Cost, usage.todayCost, usage.weekCost]
            .map { String(Int(($0 * 100).rounded())) }
            .joined(separator: ",")
        return "U,\(usage.weekday),\(days),\(usage.h5),\(usage.msgs),\(limits),\(costs)\n"
    }
}
