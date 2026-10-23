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
                let cache_read_input_tokens: Int?
            }
            let id: String?
            let model: String?
            let usage: Usage?
        }
        let message: Message?
        let timestamp: String?
        let requestId: String?
    }

    private struct Record {
        let key: String
        let model: String?
        let input: Int
        let output: Int
        let cacheWrite: Int
        let cacheRead: Int
        let timestamp: Date

        // Matches the firmware's/pre-existing total: cache reads aren't counted here
        // (they're tracked separately below for the per-type breakdown).
        var tokens: Int { input + output + cacheWrite }

        var cost: Double {
            Pricing.cost(model: model, input: input, output: output, cacheWrite: cacheWrite, cacheRead: cacheRead)
        }
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

        var todayInput = 0, todayOutput = 0, todayCacheWrite = 0, todayCost = 0.0
        var h5Input = 0, h5Output = 0, h5CacheWrite = 0, h5Cost = 0.0

        for cache in fileCaches.values {
            for rec in cache.records {
                if rec.key != "|" {
                    if seen.contains(rec.key) { continue }
                    seen.insert(rec.key)
                }
                if rec.timestamp < start { continue }

                let idx = cal.dateComponents([.day], from: start, to: cal.startOfDay(for: rec.timestamp)).day ?? -1
                if idx >= 0 && idx < 7 { days[idx] += rec.tokens }
                if idx == 6 {
                    msgs += 1
                    todayInput += rec.input
                    todayOutput += rec.output
                    todayCacheWrite += rec.cacheWrite
                    todayCost += rec.cost
                }
                if rec.timestamp >= fiveHoursAgo {
                    h5 += rec.tokens
                    h5Input += rec.input
                    h5Output += rec.output
                    h5CacheWrite += rec.cacheWrite
                    h5Cost += rec.cost
                }
            }
        }

        return buildUsage(
            now: now, days: days, h5: h5, msgs: msgs,
            todayInput: todayInput, todayOutput: todayOutput,
            todayCacheWrite: todayCacheWrite, todayCost: todayCost,
            h5Input: h5Input, h5Output: h5Output,
            h5CacheWrite: h5CacheWrite, h5Cost: h5Cost
        )
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
            records.append(Record(
                key: key,
                model: entry.message?.model,
                input: usage.input_tokens ?? 0,
                output: usage.output_tokens ?? 0,
                cacheWrite: usage.cache_creation_input_tokens ?? 0,
                cacheRead: usage.cache_read_input_tokens ?? 0,
                timestamp: t
            ))
        }

        fileCaches[path] = FileCache(offset: newOffset, mtime: mtime, records: records)
    }

    private func buildUsage(
        now: Date, days: [Int], h5: Int, msgs: Int,
        todayInput: Int, todayOutput: Int, todayCacheWrite: Int, todayCost: Double,
        h5Input: Int, h5Output: Int, h5CacheWrite: Int, h5Cost: Double
    ) -> Usage {
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
        u.todayInput = todayInput
        u.todayOutput = todayOutput
        u.todayCacheWrite = todayCacheWrite
        u.todayCost = todayCost
        u.h5Input = h5Input
        u.h5Output = h5Output
        u.h5CacheWrite = h5CacheWrite
        u.h5Cost = h5Cost
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
