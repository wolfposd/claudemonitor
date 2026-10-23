import SwiftUI

/// Plain-text style that breaks tokens out into the four types the API bills
/// separately, instead of the single lumped total the other styles show.
struct SystemVerboseView: View {
    let usage: Usage
    let lastError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("System Verbose", systemImage: "terminal")
                    .font(.headline)
                Spacer()
                statusBadge
            }

            tokenTable

            VStack(spacing: 10) {
                limitRow(title: "SESSION", pct: usage.pct5, resetMin: usage.reset5Min)
                limitRow(title: "WEEKLY", pct: usage.pct7, resetMin: usage.reset7Min)
            }

            if let lastError {
                Text(lastError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
    }

    private var tokenTable: some View {
        Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 6) {
            GridRow {
                Text("").gridColumnAlignment(.leading)
                columnHeader("input")
                columnHeader("output")
                columnHeader("input (c)")
                columnHeader("cost")
            }
            Divider().gridCellColumns(5)
            GridRow {
                Text("TODAY").font(.caption).foregroundStyle(.secondary).gridColumnAlignment(.leading)
                tokenCell(usage.todayInput, color: .pink)
                tokenCell(usage.todayOutput, color: .cyan)
                tokenCell(usage.todayCacheWrite, color: .orange)
                costCell(usage.todayCost)
            }
            GridRow {
                Text("LAST 5H").font(.caption).foregroundStyle(.secondary).gridColumnAlignment(.leading)
                tokenCell(usage.h5Input, color: .pink)
                tokenCell(usage.h5Output, color: .cyan)
                tokenCell(usage.h5CacheWrite, color: .orange)
                costCell(usage.h5Cost)
            }
        }
    }

    private func columnHeader(_ title: String) -> some View {
        Text(title).font(.caption2).foregroundStyle(.secondary)
    }

    private func tokenCell(_ value: Int, color: Color) -> some View {
        Text(TokenFormatting.format(value))
            .font(.system(.body, design: .monospaced).bold())
            .foregroundStyle(color)
    }

    private func costCell(_ value: Double) -> some View {
        Text(TokenFormatting.formatCost(value))
            .font(.system(.body, design: .monospaced).bold())
            .foregroundStyle(.green)
    }

    private var statusBadge: some View {
        Group {
            if !usage.isValid {
                Label("waiting", systemImage: "hourglass")
            } else if usage.isStale {
                Label("stale", systemImage: "exclamationmark.triangle.fill")
            } else {
                Label("live", systemImage: "circle.fill")
            }
        }
        .font(.caption2)
        .foregroundStyle(usage.isStale ? .red : .green)
    }

    private func limitRow(title: String, pct: Int?, resetMin: Int?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                if let pct {
                    Text("\(pct)%").font(.caption.bold()).foregroundStyle(color(for: pct))
                } else {
                    Text("--").font(.caption).foregroundStyle(.secondary)
                }
                if let resetMin {
                    Text("· resets in \(Self.formatDuration(resetMin))").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Gauge(value: Double(pct ?? 0), in: 0...100) { EmptyView() }
                .tint(color(for: pct ?? 0))
        }
    }

    private func color(for pct: Int) -> Color {
        if pct >= 90 { return .red }
        if pct >= 70 { return .orange }
        return .accentColor
    }

    private static func formatDuration(_ totalMinutes: Int) -> String {
        let d = totalMinutes / 1440
        let h = (totalMinutes % 1440) / 60
        let m = totalMinutes % 60
        var parts: [String] = []
        if d > 0 { parts.append("\(d)d") }
        if d > 0 || h > 0 { parts.append("\(h)h") }
        parts.append("\(m)m")
        return parts.joined(separator: " ")
    }
}
