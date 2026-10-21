import SwiftUI
import Charts

struct NativeDashboardView: View {
    let usage: Usage
    let lastError: String?

    private static let letters = ["M", "D", "M", "D", "F", "S", "S"] // Mo Di Mi Do Fr Sa So

    private var dayPoints: [(label: String, tokens: Int, isToday: Bool)] {
        (0..<7).map { i in
            let wd = ((usage.weekday - (6 - i)) % 7 + 7) % 7
            return (Self.letters[wd], usage.day[i], i == 6)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Claude Usage", systemImage: "bolt.fill")
                    .font(.headline)
                Spacer()
                statusBadge
            }

            HStack(spacing: 12) {
                statTile(title: "TODAY", value: TokenFormatting.format(usage.today), color: .pink)
                statTile(title: "LAST 5H", value: TokenFormatting.format(usage.h5), color: .yellow)
                statTile(title: "MSGS", value: "\(usage.msgs)", color: .purple)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("7-DAY TOKENS (\(TokenFormatting.format(usage.sevenDayTotal)))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Chart(Array(dayPoints.enumerated()), id: \.offset) { _, point in
                    BarMark(
                        x: .value("Day", point.label),
                        y: .value("Tokens", point.tokens)
                    )
                    .foregroundStyle(point.isToday ? Color.accentColor : Color.secondary.opacity(0.6))
                }
                .chartYAxis {
                    AxisMarks { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let tokens = value.as(Int.self) {
                                Text(TokenFormatting.format(tokens))
                            }
                        }
                    }
                }
                .frame(height: 80)
            }

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

    private func statTile(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.title3.bold()).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
