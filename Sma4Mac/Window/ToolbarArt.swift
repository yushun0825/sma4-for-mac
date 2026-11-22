import AppKit

/// ツールバーの絵(Sma4 for Mac で描いたもの)。19×19 点の線画で、どの倍率の画面でもくっきり出る。
/// 番号は ToolbarStrip.Spec.glyph と同じ。
enum ToolbarArt {
    static let size = NSSize(width: 19, height: 19)

    static func glyph(_ n: Int) -> NSImage {
        let img = NSImage(size: size, flipped: true) { _ in
            ToolbarArt.draw(n)
            return true
        }
        img.isTemplate = false
        return img
    }

    // MARK: - 絵

    private static func draw(_ n: Int) {
        let ink = NSColor(white: 0.16, alpha: 1)
        let accent = NSColor(srgbRed: 0.12, green: 0.42, blue: 0.86, alpha: 1)
        let pale = NSColor(srgbRed: 0.80, green: 0.88, blue: 0.98, alpha: 1)
        let red = NSColor(srgbRed: 0.86, green: 0.20, blue: 0.18, alpha: 1)

        func stroke(_ p: NSBezierPath, _ c: NSColor, _ w: CGFloat = 1.2) {
            c.setStroke(); p.lineWidth = w; p.lineCapStyle = .round; p.lineJoinStyle = .round; p.stroke()
        }
        func fill(_ p: NSBezierPath, _ c: NSColor) { c.setFill(); p.fill() }
        func line(_ pts: [CGPoint]) -> NSBezierPath {
            let p = NSBezierPath()
            p.move(to: pts[0])
            for q in pts.dropFirst() { p.line(to: q) }
            return p
        }
        func text(_ s: String, _ font: NSFont, _ c: NSColor, dy: CGFloat = 0) {
            let a: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: c]
            let sz = (s as NSString).size(withAttributes: a)
            (s as NSString).draw(at: NSPoint(x: (19 - sz.width) / 2, y: (19 - sz.height) / 2 + dy), withAttributes: a)
        }
        /// 紙(右上を折った長方形)
        func sheet(_ r: NSRect) -> NSBezierPath {
            let f: CGFloat = 3
            return line([CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX - f, y: r.minY), CGPoint(x: r.maxX, y: r.minY + f),
                         CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.minX, y: r.minY)])
        }

        switch n {
        case 0:  // すべて消す: 紙に赤い ×
            let s = sheet(NSRect(x: 3.5, y: 2.5, width: 10, height: 14))
            fill(s, .white); stroke(s, ink)
            fill(NSBezierPath(ovalIn: NSRect(x: 9, y: 9, width: 9, height: 9)), .white)
            stroke(line([CGPoint(x: 11, y: 11), CGPoint(x: 16, y: 16)]), red, 1.8)
            stroke(line([CGPoint(x: 16, y: 11), CGPoint(x: 11, y: 16)]), red, 1.8)
        case 1:  // 開く: フォルダから出る矢印
            let f = line([CGPoint(x: 2.5, y: 7.5), CGPoint(x: 6.5, y: 7.5), CGPoint(x: 8, y: 9), CGPoint(x: 16.5, y: 9),
                          CGPoint(x: 16.5, y: 16.5), CGPoint(x: 2.5, y: 16.5), CGPoint(x: 2.5, y: 7.5)])
            fill(f, pale); stroke(f, ink)
            stroke(line([CGPoint(x: 8.5, y: 13.5), CGPoint(x: 14, y: 3)]), accent, 1.5)
            let head = line([CGPoint(x: 15, y: 1.2), CGPoint(x: 10.8, y: 3.4), CGPoint(x: 15.2, y: 5.6), CGPoint(x: 15, y: 1.2)])
            fill(head, accent)
        case 2:  // プレビュー: 紙と虫眼鏡
            let s = sheet(NSRect(x: 2.5, y: 2.5, width: 10, height: 13.5))
            fill(s, .white); stroke(s, ink)
            for y: CGFloat in [6.5, 9, 11.5] { stroke(line([CGPoint(x: 4.8, y: y), CGPoint(x: 8.5, y: y)]), ink.withAlphaComponent(0.55), 1) }
            let lens = NSBezierPath(ovalIn: NSRect(x: 8.5, y: 7.5, width: 7, height: 7))
            fill(lens, NSColor.white.withAlphaComponent(0.85)); stroke(lens, accent, 1.5)
            stroke(line([CGPoint(x: 14.4, y: 13.4), CGPoint(x: 17.2, y: 16.2)]), ink, 2)
        case 3:  // 印刷: プリンタ
            let paperIn = NSBezierPath(rect: NSRect(x: 5.5, y: 2.5, width: 8, height: 5))
            fill(paperIn, .white); stroke(paperIn, ink)
            let body = NSBezierPath(roundedRect: NSRect(x: 2.5, y: 7.5, width: 14, height: 6.5), xRadius: 1.5, yRadius: 1.5)
            fill(body, pale); stroke(body, ink)
            let paperOut = NSBezierPath(rect: NSRect(x: 5.5, y: 11.5, width: 8, height: 5))
            fill(paperOut, .white); stroke(paperOut, ink)
            fill(NSBezierPath(ovalIn: NSRect(x: 13.2, y: 9, width: 1.6, height: 1.6)), accent)
        case 4:  // 文字
            text("A", NSFont.systemFont(ofSize: 14, weight: .semibold), ink)
            stroke(line([CGPoint(x: 4.5, y: 16.5), CGPoint(x: 14.5, y: 16.5)]), accent, 1.2)
        case 5:  // 枠: 影の付いた四角
            fill(NSBezierPath(rect: NSRect(x: 5, y: 6, width: 11.5, height: 9)), ink.withAlphaComponent(0.35))
            let r = NSBezierPath(rect: NSRect(x: 2.5, y: 3.5, width: 11.5, height: 9))
            fill(r, pale); stroke(r, ink)
        case 6:  // 矢印
            stroke(line([CGPoint(x: 3, y: 16), CGPoint(x: 13.5, y: 5.5)]), accent, 1.6)
            let head = line([CGPoint(x: 16.5, y: 2.5), CGPoint(x: 10.2, y: 4.6), CGPoint(x: 14.4, y: 8.8), CGPoint(x: 16.5, y: 2.5)])
            fill(head, accent)
        case 7:  // トリミング: 点線の範囲と四隅の印
            let r = NSBezierPath(rect: NSRect(x: 5.5, y: 5.5, width: 8, height: 8))
            r.setLineDash([1.6, 1.4], count: 2, phase: 0)
            stroke(r, accent, 1.1)
            for (cx, cy, sx, sy): (CGFloat, CGFloat, CGFloat, CGFloat) in [(2, 2, 1, 1), (17, 2, -1, 1), (2, 17, 1, -1), (17, 17, -1, -1)] {
                stroke(line([CGPoint(x: cx, y: cy + 3.5 * sy), CGPoint(x: cx, y: cy), CGPoint(x: cx + 3.5 * sx, y: cy)]), ink, 1.3)
            }
        case 8:  // 値を読む: 軸と曲線と十字
            stroke(line([CGPoint(x: 3, y: 2.5), CGPoint(x: 3, y: 16), CGPoint(x: 16.5, y: 16)]), ink, 1.1)
            let c = NSBezierPath()
            c.move(to: CGPoint(x: 4, y: 14))
            c.curve(to: CGPoint(x: 16, y: 4), controlPoint1: CGPoint(x: 9, y: 14), controlPoint2: CGPoint(x: 11, y: 5))
            stroke(c, accent, 1.4)
            stroke(line([CGPoint(x: 11.5, y: 3.5), CGPoint(x: 11.5, y: 13)]), red, 0.9)
            stroke(line([CGPoint(x: 6.5, y: 8.2), CGPoint(x: 16.5, y: 8.2)]), red, 0.9)
            stroke(NSBezierPath(ovalIn: NSRect(x: 9.9, y: 6.6, width: 3.2, height: 3.2)), red, 1.1)
        case 9:  // 定数
            let font = NSFont(name: "Times-Italic", size: 14) ?? NSFont.systemFont(ofSize: 13)
            text("a=", font, ink, dy: -1)
            stroke(line([CGPoint(x: 3.5, y: 17), CGPoint(x: 15.5, y: 17)]), accent, 1.2)
        case 10, 11:  // 上へ・下へ: 重なった四角のうち選んだほう(青)を前・後ろへ
            let back = NSBezierPath(rect: NSRect(x: 2.5, y: 2.5, width: 9, height: 9))
            let front = NSBezierPath(rect: NSRect(x: 7.5, y: 7.5, width: 9, height: 9))
            if n == 10 {
                fill(back, .white); stroke(back, ink)
                fill(front, pale); stroke(front, accent, 1.4)
            } else {
                fill(back, pale); stroke(back, accent, 1.4)
                fill(front, .white); stroke(front, ink)
            }
        case 12:  // 描き直す: 回る矢印
            let center = CGPoint(x: 9.5, y: 9.8), r: CGFloat = 5.6
            func at(_ deg: CGFloat) -> CGPoint {
                let t = deg * .pi / 180
                return CGPoint(x: center.x + r * cos(t), y: center.y - r * sin(t))
            }
            var pts: [CGPoint] = []
            var a: CGFloat = 110
            while a <= 380 { pts.append(at(a)); a += 6 }
            stroke(line(pts), ink, 1.6)
            let t: CGFloat = 380 * .pi / 180
            let end = at(380)
            let dir = CGPoint(x: -sin(t), y: -cos(t))
            let nrm = CGPoint(x: cos(t), y: -sin(t))
            let tip = CGPoint(x: end.x + dir.x * 3, y: end.y + dir.y * 3)
            let headPath = line([tip, CGPoint(x: end.x + nrm.x * 2.6, y: end.y + nrm.y * 2.6),
                                 CGPoint(x: end.x - nrm.x * 2.6, y: end.y - nrm.y * 2.6), tip])
            fill(headPath, ink)
        case 13:  // ヘルプ
            let c = NSBezierPath(ovalIn: NSRect(x: 2.5, y: 2.5, width: 14, height: 14))
            fill(c, pale); stroke(c, accent, 1.3)
            text("?", NSFont.systemFont(ofSize: 11, weight: .bold), accent)
        default:
            break
        }
    }
}
