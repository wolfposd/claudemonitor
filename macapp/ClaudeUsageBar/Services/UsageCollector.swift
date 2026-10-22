import Foundation

/// Port of `tools/usage_push.py`'s `collect()`: scans `~/.claude/projects/**/*.jsonl`
/// for `usage` entries and buckets token counts by day / last-5h window.
///
/// Parsed lines are cached per-file (by byte offset + mtime), so a poll only re-reads
/// and re-decodes the bytes appended since the previous poll instead of the whole file —
/// this runs on a timer, and a full rescan of every session transcript every 30s is real
/// disk I/O + CPU that adds up over a long-running menu bar app.
actor UsageCollector {
    private static let shared = UsageCollector()
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

    private struct Record {
        let key: String
        let tokens: Int
        let timestamp: Date
    }

    private struct FileCache {
        var offset: UInt64
        var mtime: Date
        var records: [Record]
    }

    private var fileCaches: [String: FileCache] = [:]

    static func collect() async -> Usage {
        await shared.collectImpl()
    }

    private func collectImpl() -> Usage {
        let now = Date()
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .current

        let today = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .day, value: -6, to: today)!
        let fiveHoursAgo = now.addingTimeInterval(-5 * 3600)

        let fm = FileManager.default
        var currentPaths = Set<String>()

        if let enumerator = fm.enumerator(
            at: URL(fileURLWithPath: Self.projectsDir),
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) {
            for case let url as URL in enumerator {
                guard url.pathExtension == "jsonl" else { continue }
                guard let mtime = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate, mtime >= start else { continue }

                let path = url.path
                currentPaths.insert(path)
                updateCache(for: path, mtime: mtime)
            }
        }

        // Drop cached files that fell out of the 7-day window or were removed.
        fileCaches = fileCaches.filter { currentPaths.contains($0.key) }

        var days = [Int](repeating: 0, count: 7)
        var h5 = 0
        var msgs = 0
        var seen = Set<String>()

        for cache in fileCaches.values {
            for rec in cache.records {
                if rec.key != "|" {
                    if seen.contains(rec.key) { continue }
                    seen.insert(rec.key)
                }
                if rec.timestamp < start { continue }

                let idx = cal.dateComponents([.day], from: start, to: cal.startOfDay(for: rec.timestamp)).day ?? -1
                if idx >= 0 && idx < 7 { days[idx] += rec.tokens }
                if idx == 6 { msgs += 1 }
                if rec.timestamp >= fiveHoursAgo { h5 += rec.tokens }
            }
        }

        return buildUsage(now: now, days: days, h5: h5, msgs: msgs)
    }

    /// Reads only the bytes appended to `path` since the last cached offset (or the
    /// whole file the first time it's seen), and appends newly-parsed records.
    private func updateCache(for path: String, mtime: Date) {
        let existing = fileCaches[path]
        if let existing, existing.mtime == mtime {
            return // untouched since last poll — nothing to do
        }

        guard let handle = FileHandle(forReadingAtPath: path) else { return }
        defer { try? handle.close() }

        let fileSize = handle.seekToEndOfFile()
        let seekOffset = (existing != nil && fileSize >= existing!.offset) ? existing!.offset : 0
        handle.seek(toFileOffset: seekOffset)

        let data = handle.readDataToEndOfFile()
        guard !data.isEmpty, let lastNL = data.lastRange(of: Data([0x0A])) else {
            // No new complete line yet — keep the same offset so it's re-read next time.
            fileCaches[path] = FileCache(offset: seekOffset, mtime: mtime, records: existing?.records ?? [])
            return
        }

        let completeData = data.subdata(in: data.startIndex..<lastNL.upperBound)
        let newOffset = seekOffset + UInt64(completeData.count)
        var records = existing?.records ?? []

        let text = String(data: completeData, encoding: .utf8) ?? ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard line.contains("\"usage\"") else { continue }
            guard let lineData = line.data(using: .utf8),
                  let entry = try? JSONDecoder().decode(LogLine.self, from: lineData),
                  let usage = entry.message?.usage,
                  let ts = entry.timestamp,
                  let t = Self.parseISO8601(ts) else { continue }

            let key = (entry.message?.id ?? "") + "|" + (entry.requestId ?? "")
            let tok = (usage.input_tokens ?? 0) + (usage.output_tokens ?? 0)
                + (usage.cache_creation_input_tokens ?? 0)
            records.append(Record(key: key, tokens: tok, timestamp: t))
        }

        fileCaches[path] = FileCache(offset: newOffset, mtime: mtime, records: records)
    }

    private func buildUsage(now: Date, days: [Int], h5: Int, msgs: Int) -> Usage {
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

    nonisolated static func parseISO8601(_ s: String) -> Date? {
        isoFormatterFractional.date(from: s) ?? isoFormatter.date(from: s)
    }
}
