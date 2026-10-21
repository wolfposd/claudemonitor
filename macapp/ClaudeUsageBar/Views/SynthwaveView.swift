import SwiftUI

/// Canvas recreation of the ESP32 firmware's synthwave usage display (espclaude/espclaude.ino).
/// Not pixel-perfect (the firmware's scanline sun cutout is simplified to a plain gradient disc)
/// but matches the same visual language: colors, layout, thresholds.
struct SynthwaveView: View {
    let usage: Usage

    private let scrW: CGFloat = 320
    private let scrH: CGFloat = 172
    private let horizon: CGFloat = 112

    var body: some View {
        Canvas { ctx, size in
            let sx = size.width / scrW
            let sy = size.height / scrH
            ctx.scaleBy(x: sx, y: sy)

            drawBackground(&ctx)
            drawHeader(&ctx)
            drawStats(&ctx)
            drawBars(&ctx)
            drawLimits(&ctx)
        }
        .frame(width: scrW * 1.4, height: scrH * 1.4)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .padding(12)
    }

    // MARK: - color helpers (port of C() / mix())

    private func c(_ r: Int, _ g: Int, _ b: Int) -> Color {
        Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
    }

    private func mix(_ r1: Int, _ g1: Int, _ b1: Int, _ r2: Int, _ g2: Int, _ b2: Int, _ t: Int, _ tmax: Int) -> Color {
        func lerp(_ a: Int, _ b: Int) -> Int { tmax == 0 ? a : a + (b - a) * t / tmax }
        return c(lerp(r1, r2), lerp(g1, g2), lerp(b1, b2))
    }

    // MARK: - background

    private func drawBackground(_ ctx: inout GraphicsContext) {
        var y = 0
        while CGFloat(y) < horizon {
            let col = mix(8, 0, 22, 48, 0, 62, y, Int(horizon))
            ctx.fill(Path(CGRect(x: 0, y: CGFloat(y), width: scrW, height: 2)), with: .color(col))
            y += 2
        }
        let cx: CGFloat = 236, cy = horizon, r: CGFloat = 46
        let sunRect = CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2)
        ctx.fill(Path(ellipseIn: sunRect), with: .linearGradient(
            Gradient(colors: [c(120, 20, 90), c(150, 70, 20)]),
            startPoint: CGPoint(x: cx, y: cy - r),
            endPoint: CGPoint(x: cx, y: cy)))

        ctx.fill(Path(CGRect(x: 0, y: horizon, width: scrW, height: scrH - horizon)), with: .color(c(14, 0, 30)))
        ctx.fill(Path(CGRect(x: 0, y: horizon, width: scrW, height: 1)), with: .color(c(0, 240, 255)))
    }

    private func drawHeader(_ ctx: inout GraphicsContext) {
        glowText(&ctx, x: 8, y: 2, "CLAUDE", size: 20, col: c(255, 60, 200), shadow: c(0, 200, 255))
        ctx.draw(Text("USAGE").font(.system(size: 10, design: .monospaced)).foregroundColor(c(0, 240, 255)),
                  at: CGPoint(x: 104 + 20, y: 15), anchor: .center)
        var x = 0
        while CGFloat(x) < scrW {
            let col = mix(255, 40, 200, 0, 240, 255, x, Int(scrW))
            ctx.fill(Path(CGRect(x: CGFloat(x), y: 22, width: 2, height: 1)), with: .color(col))
            x += 2
        }
    }

    private func drawStats(_ ctx: inout GraphicsContext) {
        ctx.draw(Text("TODAY").font(.system(size: 9, design: .monospaced)).foregroundColor(c(0, 240, 255)),
                  at: CGPoint(x: 8 + 20, y: 30), anchor: .center)
        ctx.draw(Text("\(usage.msgs) MSGS").font(.system(size: 9, design: .monospaced)).foregroundColor(c(190, 150, 255)),
                  at: CGPoint(x: 8 + 6 * 7 + 20, y: 30), anchor: .center)
        glowText(&ctx, x: 8, y: 38, TokenFormatting.format(usage.today), size: 28, col: c(255, 70, 210), shadow: c(70, 0, 140))

        ctx.draw(Text("LAST 5H").font(.system(size: 9, design: .monospaced)).foregroundColor(c(0, 240, 255)),
                  at: CGPoint(x: 8 + 24, y: 73), anchor: .center)
        glowText(&ctx, x: 8, y: 81, TokenFormatting.format(usage.h5), size: 28, col: c(255, 230, 80), shadow: c(120, 60, 0))
    }

    private func drawBars(_ ctx: inout GraphicsContext) {
        let mx = max(1, usage.day.max() ?? 1)
        let total = usage.sevenDayTotal
        let letters: [Character] = Array("MDMDFSS") // Mo Di Mi Do Fr Sa So
        let x0: CGFloat = 170, bw: CGFloat = 16, gap: CGFloat = 4, base: CGFloat = 100, maxh: CGFloat = 56

        ctx.draw(Text("7D \(TokenFormatting.format(total))").font(.system(size: 9, design: .monospaced))
                    .foregroundColor(c(255, 255, 255)),
                  at: CGPoint(x: x0 + 35, y: 30), anchor: .leading)

        for i in 0..<7 {
            let h = usage.day[i] > 0 ? max(2, CGFloat(usage.day[i]) * maxh / CGFloat(mx)) : 0
            let x = x0 + CGFloat(i) * (bw + gap)
            var y: CGFloat = 0
            while y < h {
                let col = mix(0, 240, 255, 255, 40, 200, Int(y), Int(maxh))
                ctx.fill(Path(CGRect(x: x, y: base - h + y, width: bw, height: 2)), with: .color(col))
                y += 2
            }
            if i == 6 && h > 0 {
                ctx.fill(Path(CGRect(x: x, y: base - h, width: bw, height: 1)), with: .color(.white))
            }
            let wd = ((usage.weekday - (6 - i)) % 7 + 7) % 7
            let letterColor = i == 6 ? Color.white : c(190, 150, 255)
            ctx.draw(Text(String(letters[wd])).font(.system(size: 9, design: .monospaced)).foregroundColor(letterColor),
                      at: CGPoint(x: x + bw / 2, y: base + 8), anchor: .center)
        }
        ctx.fill(Path(CGRect(x: x0 - 2, y: base + 1, width: 7 * (bw + gap), height: 1)), with: .color(c(255, 40, 200)))
    }

    private func drawLimits(_ ctx: inout GraphicsContext) {
        drawLimitBar(&ctx, y: 118, label: "SESSION", pct: usage.pct5)
        drawLimitBar(&ctx, y: 137, label: "WEEKLY", pct: usage.pct7)
    }

    private func drawLimitBar(_ ctx: inout GraphicsContext, y: CGFloat, label: String, pct: Int?) {
        let segs = 20, segW: CGFloat = 10, h: CGFloat = 14, x0: CGFloat = 60
        ctx.draw(Text(label).font(.system(size: 9, design: .monospaced)).foregroundColor(c(0, 240, 255)),
                  at: CGPoint(x: 8, y: y + 7), anchor: .leading)

        let filled = pct.map { min(segs, ($0 * segs + 50) / 100) } ?? 0
        for i in 0..<segs {
            let col = i < filled ? mix(0, 240, 255, 255, 40, 200, i, segs - 1) : c(40, 10, 70)
            ctx.fill(Path(CGRect(x: x0 + CGFloat(i) * segW, y: y, width: segW - 2, height: h)), with: .color(col))
        }

        let label2 = pct.map { "\($0)%" } ?? "--%"
        let pc: Color = {
            guard let pct else { return c(255, 255, 255) }
            if pct >= 90 { return c(255, 50, 60) }
            if pct >= 70 { return c(255, 140, 40) }
            return c(255, 255, 255)
        }()
        glowText(&ctx, x: x0 + CGFloat(segs) * segW + 8, y: y - 3, label2, size: 14, col: pc, shadow: c(70, 0, 140))
    }


    // MARK: - glow text (double-draw, port of glowText())

    private func glowText(_ ctx: inout GraphicsContext, x: CGFloat, y: CGFloat, _ s: String, size: CGFloat, col: Color, shadow: Color) {
        let font = Font.system(size: size, weight: .bold, design: .monospaced)
        ctx.draw(Text(s).font(font).foregroundColor(shadow), at: CGPoint(x: x + 1, y: y + 1 + size / 2), anchor: .leading)
        ctx.draw(Text(s).font(font).foregroundColor(col), at: CGPoint(x: x, y: y + size / 2), anchor: .leading)
    }
}
