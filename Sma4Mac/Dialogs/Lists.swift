import AppKit
import Sma4Core

/// ダイアログの選択肢
@MainActor
enum Lists {
    static let lineTypes = ["線なし", "実線", "破線", "点線", "一点鎖線", "二点鎖線"]
    static let fontStyles = ["Regular", "Italic", "Bold", "Bold Italic"]
    static let fontSizes = ["6", "7", "8", "9", "10", "11", "12", "14", "16", "18", "20", "22", "24", "26", "28", "36", "48", "72"]
    static let angles = ["0", "90", "180", "270"]
    /// Dot の線種(区点を結ぶ形)
    static let dotLineStyles = ["なし", "矩形", "連続直線", "多角形", "曲線", "閉曲線", "縦階段", "横階段"]
    static let paperSizes: [(String, Int, Int)] = [("A3", 297, 420), ("A4", 210, 297), ("A5", 148, 210), ("B4", 257, 364), ("B5", 182, 257),
                                                   ("Letter", 216, 279), ("ユーザー定義", 0, 0)]
    static let printScales = ["50", "70", "100", "141", "150", "200"]

    /// 色の一覧(Windows の 16 色)
    static let colors: [(String, SMPColor)] = [
        ("黒", SMPColor(r: 0, g: 0, b: 0)), ("赤", SMPColor(r: 255, g: 0, b: 0)), ("緑", SMPColor(r: 0, g: 255, b: 0)),
        ("青", SMPColor(r: 0, g: 0, b: 255)), ("黄", SMPColor(r: 255, g: 255, b: 0)), ("紫", SMPColor(r: 255, g: 0, b: 255)),
        ("水色", SMPColor(r: 0, g: 255, b: 255)), ("白", SMPColor(r: 255, g: 255, b: 255)), ("灰", SMPColor(r: 128, g: 128, b: 128)),
        ("茶", SMPColor(r: 128, g: 0, b: 0)), ("深緑", SMPColor(r: 0, g: 128, b: 0)), ("紺", SMPColor(r: 0, g: 0, b: 128)),
        ("オリーブ", SMPColor(r: 128, g: 128, b: 0)), ("赤紫", SMPColor(r: 128, g: 0, b: 128)), ("青緑", SMPColor(r: 0, g: 128, b: 128)),
        ("銀", SMPColor(r: 192, g: 192, b: 192)),
    ]

    /// 欧文フォント(Windows でよく使う名前を先に、Mac にあるものも入れる)
    static func latinFonts() -> [String] {
        var names = ["Times New Roman", "Arial", "Courier New", "Helvetica", "Times", "Symbol"]
        let mac = NSFontManager.shared.availableFontFamilies.filter { !$0.hasPrefix(".") }
        for n in mac where !names.contains(n) && !n.unicodeScalars.contains(where: { FontMapper.isJapanese($0) }) { names.append(n) }
        return names
    }

    static func japaneseFonts() -> [String] {
        var names = ["ＭＳ 明朝", "ＭＳ ゴシック", "ＭＳ Ｐ明朝", "ＭＳ Ｐゴシック"]
        for n in ["Hiragino Mincho ProN", "Hiragino Sans", "Hiragino Kaku Gothic ProN", "YuMincho", "YuGothic", "Osaka"] where !names.contains(n) {
            if NSFontManager.shared.availableFontFamilies.contains(n) { names.append(n) }
        }
        return names
    }

    // MARK: - 絵の付いた選択肢

    static func swatch(_ c: SMPColor, size: NSSize = NSSize(width: 28, height: 11)) -> NSImage {
        NSImage(size: size, flipped: true) { r in
            c.nsColor.setFill()
            r.insetBy(dx: 0.5, dy: 0.5).fill()
            NSColor.black.setStroke()
            NSBezierPath(rect: r.insetBy(dx: 0.5, dy: 0.5)).stroke()
            return true
        }
    }

    static func colorItems() -> [(title: String, image: NSImage?)] {
        colors.map { ($0.0, swatch($0.1)) } + [("その他…", nil)]
    }

    static func colorIndex(_ c: SMPColor) -> Int? { colors.firstIndex { $0.1 == c } }

    /// 線の見本
    static func lineImage(_ type: Int, width: CGFloat = 48) -> NSImage {
        NSImage(size: NSSize(width: width, height: 11), flipped: true) { r in
            guard type > 0, let ctx = NSGraphicsContext.current?.cgContext else { return true }
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(1)
            let d = GraphRenderer.dash(type, pitch: 300, width: 40).map { $0 / 40 }
            if !d.isEmpty { ctx.setLineDash(phase: 0, lengths: d) }
            ctx.move(to: CGPoint(x: 1, y: r.midY)); ctx.addLine(to: CGPoint(x: r.maxX - 1, y: r.midY))
            ctx.strokePath()
            return true
        }
    }

    static func lineTypeItems(includeFill: Bool = false) -> [(title: String, image: NSImage?)] {
        var items: [(title: String, image: NSImage?)] = lineTypes.enumerated().map { i, t in (t, i == 0 ? nil : lineImage(i)) }
        if includeFill { items.append(("面", nil)) }
        return items
    }

    /// プロットタイプの選択肢(文字で表すもの以外は形を描く。黒い線と白い中)
    static func plotTypeImage(_ code: Int) -> NSImage? {
        if PlotType.title(code) != nil { return nil }
        return NSImage(size: NSSize(width: 30, height: 13), flipped: true) { r in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            GraphRenderer.drawPlotMark(code: code, center: CGPoint(x: r.midX, y: r.midY), diameter: 9, dotColor: .black, lineWidth: 1,
                                       brushStyle: 0, brushColor: .white, brushHatch: 0, in: ctx)
            return true
        }
    }

    static func plotTypeItems(_ codes: [Int]) -> [(title: String, image: NSImage?)] {
        codes.map { c in (PlotType.title(c) ?? "\(c)", plotTypeImage(c)) }
    }
}

extension TemplateView {
    /// 色の選択肢の箱(その他… を選ぶと色のパネルを出す)
    func setupColorPopup(_ id: Int, color: SMPColor) {
        setImageItems(id, Lists.colorItems())
        if let i = Lists.colorIndex(color) {
            select(id, i)
        } else {
            // 一覧に無い色は「その他」の前に入れて選んでおく
            if let p = popup(id) {
                let m = NSMenuItem(title: "その他の色", action: nil, keyEquivalent: "")
                m.image = Lists.swatch(color)
                m.representedObject = color.colorref
                p.menu?.insertItem(m, at: Lists.colors.count)
                p.selectItem(at: Lists.colors.count)
            }
        }
        popup(id)?.selectedItem?.representedObject = popup(id)?.selectedItem?.representedObject
        let previous = popup(id)?.indexOfSelectedItem ?? 0
        var last = previous
        on(id) { [weak self] in
            guard let self, let p = self.popup(id) else { return }
            if p.indexOfSelectedItem == p.numberOfItems - 1 {
                // その他…: 色のパネルの代わりに色の選択の窓を出す
                let current = self.popupColor(id, fallback: color)
                if let c = ColorChooser.choose(initial: current, over: self.window) {
                    if let i = Lists.colorIndex(c) { p.selectItem(at: i) } else {
                        let m = NSMenuItem(title: "その他の色", action: nil, keyEquivalent: "")
                        m.image = Lists.swatch(c)
                        m.representedObject = c.colorref
                        if let old = p.menu?.items.firstIndex(where: { $0.representedObject != nil }) { p.menu?.removeItem(at: old) }
                        p.menu?.insertItem(m, at: Lists.colors.count)
                        p.selectItem(at: Lists.colors.count)
                    }
                } else {
                    p.selectItem(at: last)
                }
            }
            last = p.indexOfSelectedItem
        }
    }

    func popupColor(_ id: Int, fallback: SMPColor) -> SMPColor {
        guard let p = popup(id), let item = p.selectedItem else { return fallback }
        if let ref = item.representedObject as? Int { return SMPColor(colorref: ref) }
        let i = p.indexOfSelectedItem
        if i >= 0 && i < Lists.colors.count { return Lists.colors[i].1 }
        return fallback
    }
}

/// 色を 1 つ選ぶ小さな窓(NSColorPanel をモーダルの中から使う)
@MainActor
enum ColorChooser {
    static func choose(initial: SMPColor, over window: NSWindow?) -> SMPColor? {
        let well = NSColorWell(style: .expanded)
        well.color = initial.nsColor
        let panel = DialogPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 96), styleMask: [.titled], backing: .buffered, defer: true)
        panel.title = "色の選択"
        let content = FlippedView(frame: NSRect(x: 0, y: 0, width: 240, height: 96))
        well.frame = NSRect(x: 16, y: 16, width: 208, height: 28)
        content.addSubview(well)
        var result: SMPColor?
        let ok = ClosureButton(title: "OK") { result = SMPColor(well.color); NSApp.stopModal() }
        let cancel = ClosureButton(title: "キャンセル") { NSApp.stopModal() }
        ok.frame = NSRect(x: 40, y: 58, width: 88, height: 24)
        cancel.frame = NSRect(x: 132, y: 58, width: 88, height: 24)
        ok.keyEquivalent = "\r"
        cancel.keyEquivalent = "\u{1b}"
        content.addSubview(ok)
        content.addSubview(cancel)
        panel.contentView = content
        panel.worksWhenModal = true
        Dialog.place(panel, over: window)
        NSApp.runModal(for: panel)
        panel.orderOut(nil)
        NSColorPanel.shared.orderOut(nil)
        return result
    }
}

/// 押したら閉じるだけのボタン
final class ClosureButton: NSButton {
    private var handler: () -> Void = {}

    convenience init(title: String, handler: @escaping () -> Void) {
        self.init(frame: .zero)
        self.title = title
        self.bezelStyle = .push
        self.controlSize = .small
        self.font = TemplateView.font
        self.handler = handler
        self.target = self
        self.action = #selector(run(_:))
    }

    @objc private func run(_ sender: Any?) { handler() }
}
