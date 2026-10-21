import Foundation

/// Port of `tools/usage_push.py`'s `collect()`: scans `~/.claude/projects/**/*.jsonl`
/// for `usage` entries and buckets token counts by day / last-5h window.
enum UsageCollector {
    static let projectsDir = (NSHomeDirectory() as NSString).appendingPathComponent(".claude/projects")

    /// Loose shape of one JSONL line we care about.
    private struct LogLine: Decodable {
        struct Message: Decodable {
            struct Usage: Decodable {
                let input_tokens: Int?
                let output_tokens: Int?
                let cache_creation_input_tokens: Int?
            }
            let id: String?
            let usage: Usage?
        }
        let message: Message?
        let timestamp: String?
        let requestId: String?
    }

    static func collect() -> Usage {
        let now = Date()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current

        let today = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .day, value: -6, to: today)!
        let fiveHoursAgo = now.addingTimeInterval(-5 * 3600)

        var days = [Int](repeating: 0, count: 7)
        var h5 = 0
        var msgs = 0
        var seen = Set<String>()

        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: projectsDir),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else {
            return buildUsage(now: now, days: days, h5: h5, msgs: msgs)
        }

        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            guard let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate, mtime >= start else { continue }

            guard var reader = LineReader(path: url.path) else { continue }
            defer { reader.close() }

            for line in reader {
                guard line.contains("\"usage\"") else { continue }
                guard let data = line.data(using: .utf8),
                      let entry = try? JSONDecoder().decode(LogLine.self, from: data),
                      let usage = entry.message?.usage,
                      let ts = entry.timestamp,
                      let t = parseISO8601(ts) else { continue }

                let key = (entry.message?.id ?? "") + "|" + (entry.requestId ?? "")
                if key != "|" {
                    if seen.contains(key) { continue }
                    seen.insert(key)
                }
                if t < start { continue }

                let tok = (usage.input_tokens ?? 0) + (usage.output_tokens ?? 0)
                    + (usage.cache_creation_input_tokens ?? 0)
                let idx = cal.dateComponents([.day], from: start, to: cal.startOfDay(for: t)).day ?? -1
                if idx >= 0 && idx < 7 { days[idx] += tok }
                if idx == 6 { msgs += 1 }
                if t >= fiveHoursAgo { h5 += tok }
            }
        }

        return buildUsage(now: now, days: days, h5: h5, msgs: msgs)
    }

    private static func buildUsage(now: Date, days: [Int], h5: Int, msgs: Int) -> Usage {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2 // Monday
        // Foundation weekday: 1 = Sunday ... 7 = Saturday. Convert to 0 = Monday.
        let weekdaySunBased = cal.component(.weekday, from: now)
        let weekday = (weekdaySunBased + 5) % 7

        var u = Usage()
        u.weekday = weekday
        u.day = days
        u.h5 = h5
        u.msgs = msgs
        u.lastUpdated = now
        return u
    }

    private static let isoFormatterFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func parseISO8601(_ s: String) -> Date? {
        isoFormatterFractional.date(from: s) ?? isoFormatter.date(from: s)
    }
}
