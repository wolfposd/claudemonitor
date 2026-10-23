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
        guard let token = readAccessToken() else {
            return Limits(error: "Keychain item \"Claude Code-credentials\" not found. Run `claude` once.")
        }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.0", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                let hint = http.statusCode == 401 || http.statusCode == 403
                    ? " (token expired? run `claude` once)" : ""
                return Limits(error: "HTTP \(http.statusCode)\(hint)")
            }
            let decoded = try JSONDecoder().decode(UsageResponse.self, from: data)
            let (pct5, reset5) = convert(decoded.five_hour)
            let (pct7, reset7) = convert(decoded.seven_day)
            return Limits(pct5: pct5, reset5Min: reset5, pct7: pct7, reset7Min: reset7)
        } catch {
            return Limits(error: error.localizedDescription)
        }
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
