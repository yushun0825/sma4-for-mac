// アプリのアイコンを描いて PNG にする: swift Tools/make_icon.swift 出力フォルダ
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments[1])
func draw(size: Int) -> Data {
    let s = CGFloat(size)
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let k = s / 1024
    // macOS のアイコンの大きさ(1024 の中に 824 の角丸)
    let body = CGRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k)
    let path = CGPath(roundedRect: body, cornerWidth: 185 * k, cornerHeight: 185 * k, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 24 * k, color: NSColor.black.withAlphaComponent(0.28).cgColor)
    ctx.addPath(path)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [NSColor(white: 1, alpha: 1).cgColor, NSColor(white: 0.93, alpha: 1).cgColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: body.maxY), end: CGPoint(x: 0, y: body.minY), options: [])
    ctx.restoreGState()

    // グラフの枠と目盛り
    let frame = CGRect(x: 250 * k, y: 255 * k, width: 540 * k, height: 470 * k)
    ctx.setStrokeColor(NSColor(white: 0.08, alpha: 1).cgColor)
    ctx.setLineWidth(max(1, 16 * k))
    ctx.stroke(frame)
    ctx.setLineWidth(max(1, 12 * k))
    for i in 1..<5 {
        let x = frame.minX + frame.width * CGFloat(i) / 5
        ctx.move(to: CGPoint(x: x, y: frame.minY)); ctx.addLine(to: CGPoint(x: x, y: frame.minY + 34 * k))
        ctx.move(to: CGPoint(x: x, y: frame.maxY)); ctx.addLine(to: CGPoint(x: x, y: frame.maxY - 34 * k))
        let y = frame.minY + frame.height * CGFloat(i) / 5
        ctx.move(to: CGPoint(x: frame.minX, y: y)); ctx.addLine(to: CGPoint(x: frame.minX + 34 * k, y: y))
        ctx.move(to: CGPoint(x: frame.maxX, y: y)); ctx.addLine(to: CGPoint(x: frame.maxX - 34 * k, y: y))
    }
    ctx.strokePath()
    // 曲線
    let accent = NSColor(srgbRed: 0.10, green: 0.33, blue: 0.78, alpha: 1).cgColor
    ctx.setStrokeColor(accent)
    ctx.setLineWidth(max(1.2, 20 * k))
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    var first = true
    for i in 0...120 {
        let t = Double(i) / 120
        let y = 0.12 + 0.75 * exp(-pow((t - 0.55) / 0.16, 2)) + 0.05 * t
        let p = CGPoint(x: frame.minX + frame.width * CGFloat(t), y: frame.minY + frame.height * CGFloat(y))
        if first { ctx.move(to: p); first = false } else { ctx.addLine(to: p) }
    }
    ctx.strokePath()
    // データ点(白抜きの丸)
    let pts: [(Double, Double)] = [(0.1, 0.16), (0.3, 0.33), (0.45, 0.72), (0.58, 0.86), (0.72, 0.52), (0.9, 0.2)]
    for (t, y) in pts {
        let c = CGPoint(x: frame.minX + frame.width * CGFloat(t), y: frame.minY + frame.height * CGFloat(y))
        let r = 30 * k
        let rect = CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
        ctx.setFillColor(NSColor.white.cgColor); ctx.fillEllipse(in: rect)
        ctx.setStrokeColor(NSColor(white: 0.08, alpha: 1).cgColor)
        ctx.setLineWidth(max(1, 12 * k)); ctx.strokeEllipse(in: rect)
    }
    // 名前の「S4」(左上の空いたところ)
    let font = NSFont.systemFont(ofSize: 118 * k, weight: .heavy)
    let ink = NSColor(srgbRed: 0.08, green: 0.12, blue: 0.24, alpha: 1)
    ("S4" as NSString).draw(at: NSPoint(x: 284 * k, y: 588 * k), withAttributes: [.font: font, .foregroundColor: ink])
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

var images: [[String: String]] = []
for (pt, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    let px = pt * scale
    let name = "icon_\(pt)x\(pt)\(scale == 2 ? "@2x" : "").png"
    try! draw(size: px).write(to: out.appendingPathComponent(name))
    images.append(["idiom": "mac", "size": "\(pt)x\(pt)", "scale": "\(scale)x", "filename": name])
}
let json: [String: Any] = ["images": images, "info": ["version": 1, "author": "xcode"]]
let data = try! JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
try! data.write(to: out.appendingPathComponent("Contents.json"))
print("ok")
