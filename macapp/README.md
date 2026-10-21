# ClaudeUsageBar

A slim macOS menu bar app that shows the same Claude Code usage data as the physical
ESP32 display in [`../espclaude`](../espclaude), without needing the board or USB serial.

It reimplements, natively in Swift:

- **Log scanning** ([`UsageCollector`](ClaudeUsageBar/Services/UsageCollector.swift)) — ports
  `tools/usage_push.py`'s `collect()`: scans `~/.claude/projects/**/*.jsonl` for token usage,
  bucketed into the last 7 days and the last 5 hours.
- **Keychain + usage API** ([`KeychainUsageClient`](ClaudeUsageBar/Services/KeychainUsageClient.swift)) —
  ports `fetch_limits()`: reads the OAuth token Claude Code stores in the macOS Keychain
  (`"Claude Code-credentials"`, via the Security framework instead of shelling out to
  `/usr/bin/security`) and calls the same undocumented `api.anthropic.com/api/oauth/usage`
  endpoint for session (5h) / weekly (7d) limit percentages.

There is no serial/ESP integration — this app is a standalone viewer. The Python tools and
`.ino` firmware are untouched and keep working independently.

## Requirements

- Claude Code must have been run at least once on this Mac (so `~/.claude/projects` has logs
  and the Keychain has a `Claude Code-credentials` item). If the usage API returns 401/403,
  run `claude` once to refresh the token.
- The app is **unsandboxed** (no App Sandbox entitlement) so it can read the Keychain item the
  same way the Python script does, with no extra entitlement/access-group setup.

## Building & running

Project files are generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen) from
`project.yml` (not checked in as a raw `.xcodeproj` diff-magnet — regenerate after editing
`project.yml` or adding/removing files):

```bash
brew install xcodegen   # if not already installed
cd macapp
xcodegen generate
open ClaudeUsageBar.xcodeproj
```

Then build & run from Xcode (⌘R), or from the command line:

```bash
xcodebuild -project ClaudeUsageBar.xcodeproj -scheme ClaudeUsageBar -configuration Debug build
open "$(xcodebuild -project ClaudeUsageBar.xcodeproj -scheme ClaudeUsageBar -configuration Debug -showBuildSettings | awk -F'= ' '/ BUILT_PRODUCTS_DIR/{print $2; exit}')/ClaudeUsageBar.app"
```

The app has no Dock icon (menu-bar-only / `LSUIElement`); look for the bolt icon in the
menu bar. Click it to open the usage panel, refresh manually, switch between the synthwave
and native dashboard styles, or quit.

## Dashboard styles

Switchable in Settings (gear icon in the panel):

- **Synthwave** ([`SynthwaveView`](ClaudeUsageBar/Views/SynthwaveView.swift)) — a `Canvas`-based
  recreation of the ESP firmware's neon grid/sun/bar-chart look.
- **Native** ([`NativeDashboardView`](ClaudeUsageBar/Views/NativeDashboardView.swift)) — the same
  data as plain macOS UI (Swift Charts bar chart, gauges, stat tiles).
