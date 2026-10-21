import SwiftUI

/// Tiny status-item glyph: a gauge ring colored by the session (5h) limit %.
struct MenuBarIconView: View {
    let usage: Usage

    private var pct: Double {
        guard let p = usage.pct5 else { return 0 }
        return Double(p) / 100
    }

    private var tint: Color {
        guard let p = usage.pct5 else { return .secondary }
        if p >= 90 { return .red }
        if p >= 70 { return .orange }
        if p >= 50 { return .yellow }
        return .primary
    }

    var body: some View {
        Image("MenuBarIcon")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(tint)
            .frame(width: 20, height: 20)
    }
}
