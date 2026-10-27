import Foundation

/// Port of `tools/usage_push.py`'s `fetch_limits()`: reads the OAuth token Claude Code
/// stores in the macOS Keychain and calls the undocumented usage-limits endpoint.
enum KeychainUsageClient {
    struct Limits: Equatable {
        var pct5: Int?
        var reset5Min: Int?
        var pct7: Int?
        var reset7Min: Int?
        var error: String?
    }

    private struct OAuthCreds: Decodable {
        struct Inner: Decodable { let accessToken: String }
        let claudeAiOauth: Inner
    }

    private struct UsageResponse: Decodable {
        struct Window: Decodable {
            let utilization: Double?
            let resets_at: String?
        }
        let five_hour: Window?
        let seven_day: Window?
    }

    private static var cache: (fetchedAt: Date, value: Limits)?
    private static let cacheTTL: TimeInterval = 60

    static func fetchLimits() async -> Limits {
        if let cache, Date().timeIntervalSince(cache.fetchedAt) < cacheTTL {
            return cache.value
        }
        let value = await fetchLimitsUncached()
        cache = (Date(), value)
        return value
    }

    private static func fetchLimitsUncached() async -> Limits {
        guard var token = readAccessToken() else {
            return Limits(error: "Keychain item \"Claude Code-credentials\" not found. Run `claude` once.")
        }

        var result = await requestUsage(token: token)
        if result.isAuthFailure {
            // Expired token: `claude -p "/usage"` is handled locally (no model call, no cost),
            // but the CLI refreshes its OAuth token and rewrites the Keychain item on startup.
            if await refreshTokenViaCLI(), let fresh = readAccessToken(), fresh != token {
                token = fresh
                result = await requestUsage(token: token)
            }
        }
        return result.limits
    }

    private struct UsageResult {
        var limits: Limits
        var isAuthFailure = false
    }

    private static func requestUsage(token: String) async -> UsageResult {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let authFailure = http.statusCode == 401 || http.statusCode == 403
                let hint = authFailure ? " (token expired? run `claude` once)" : ""
                return UsageResult(limits: Limits(error: "HTTP \(http.statusCode)\(hint)"),
                                   isAuthFailure: authFailure)
            }
            let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
            let (pct5, reset5) = convert(decoded.five_hour)
            let (pct7, reset7) = convert(decoded.seven_day)
            return UsageResult(limits: Limits(pct5: pct5, reset5Min: reset5, pct7: pct7, reset7Min: reset7))
        } catch {
            return UsageResult(limits: Limits(error: error.localizedDescription))
        }
    }

    // MARK: - Token refresh via the Claude CLI

    /// Runs `claude -p "/usage"` so the CLI refreshes its OAuth token. Returns true if the
    /// process exited successfully within the timeout.
    private static func refreshTokenViaCLI(timeout: TimeInterval = 30) async -> Bool {
        guard let claude = locateClaudeBinary() else { return false }

        let process = Process()
        process.executableURL = claude
        process.arguments = ["-p", "/usage"]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        process.standardInput = FileHandle.nullDevice

        // GUI apps get a minimal PATH; npm-installed `claude` uses `#!/usr/bin/env node`.
        var env = ProcessInfo.processInfo.environment
        let extra = [claude.deletingLastPathComponent().path, "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        env["PATH"] = (extra + [env["PATH"] ?? ""]).joined(separator: ":")
        process.environment = env

        return await withCheckedContinuation { continuation in
            process.terminationHandler = { proc in
                continuation.resume(returning: proc.terminationStatus == 0)
            }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(returning: false)
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if process.isRunning { process.terminate() }
            }
        }
    }

    /// Finds the `claude` executable: well-known install locations first, then the user's
    /// login shell PATH (covers nvm/volta/custom prefixes).
    private static func locateClaudeBinary() -> URL? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        let candidates = [
            "\(home)/.local/bin/claude",
            "\(home)/.claude/local/claude",
            "/opt/homebrew/bin/claude",
            "/usr/local/bin/claude",
            "\(home)/.npm-global/bin/claude",
            "\(home)/.volta/bin/claude",
        ]
        if let hit = candidates.first(where: { fm.isExecutableFile(atPath: $0) }) {
            return URL(fileURLWithPath: hit)
        }

        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/zsh")
        shell.arguments = ["-ilc", "command -v claude"]
        let stdout = Pipe()
        shell.standardOutput = stdout
        shell.standardError = Pipe()
        shell.standardInput = FileHandle.nullDevice
        do { try shell.run() } catch { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        shell.waitUntilExit()

        guard shell.terminationStatus == 0,
              let path = String(data: data, encoding: .utf8)?
                .split(whereSeparator: \.isNewline).last
                .map({ $0.trimmingCharacters(in: .whitespaces) }),
              fm.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path)
    }

    private static func convert(_ window: UsageResponse.Window?) -> (Int?, Int?) {
        guard let window else { return (nil, nil) }
        let pct = window.utilization.map { Int(($0).rounded()) }
        let reset = window.resets_at.flatMap(minutesUntil)
        return (pct, reset)
    }

    private static func minutesUntil(_ iso: String) -> Int? {
        guard let date = UsageCollector.parseISO8601(iso) else { return nil }
        return max(0, Int(date.timeIntervalSinceNow / 60))
    }

    /// Reads the access token by shelling out to `security` (same as `usage_push.py`),
    /// rather than calling `SecItemCopyMatching` directly. `/usr/bin/security` is a
    /// stable, Apple-signed binary, so a Keychain "Always Allow" grant to it persists
    /// across rebuilds — unlike this app's own ad-hoc-signed binary, whose signature
    /// changes on every rebuild and would otherwise re-trigger the Keychain prompt.
    private static func readAccessToken() -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]

        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0,
              let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let jsonData = output.data(using: .utf8),
              let creds = try? JSONDecoder().decode(OAuthCreds.self, from: jsonData) else {
            return nil
        }
        return creds.claudeAiOauth.accessToken
    }
}
