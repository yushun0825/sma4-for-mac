import AppKit
import Sma4Core

/// 挿入メニューのダイアログ(文字列・矢印・Dot・枠・図)
@MainActor
enum ObjectDialogs {
    /// ダイアログの閉じ方
    enum Outcome<T> {
        case ok(T)
        case delete
        case placeWithMouse(T)
    }

    // MARK: - 文字列(SETLEGEND)

    static let specialCharacters: [(String, String)] = [
        ("上付き ^…@", "^@"), ("下付き _…@", "_@"), ("改行 \\n", "\\n"), ("α (%Ga%A)", "%Ga%A"), ("β (%Gb%A)", "%Gb%A"),
        ("γ (%Gg%A)", "%Gg%A"), ("δ (%Gd%A)", "%Gd%A"), ("Δ (%GD%A)", "%GD%A"), ("θ (%Gq%A)", "%Gq%A"), ("λ (%Gl%A)", "%Gl%A"),
        ("μ (%Gm%A)", "%Gm%A"), ("ν (%Gn%A)", "%Gn%A"), ("π (%Gp%A)", "%Gp%A"), ("σ (%Gs%A)", "%Gs%A"), ("τ (%Gt%A)", "%Gt%A"),
        ("φ (%Gf%A)", "%Gf%A"), ("ω (%Gw%A)", "%Gw%A"), ("Ω (%GW%A)", "%GW%A"), ("° (%Q176)", "%Q176"), ("± (%Q177)", "%Q177"),
        ("× (%Q215)", "%Q215"), ("Å (%Q197)", "%Q197"), ("イタリック %I", "%I"), ("ボールド %B", "%B"), ("ローマン %R", "%R"),
        ("ファイル名 %01N", "%01N"), ("ドットの見本 %01E", "%01E"), ("今日の日付 %M", "%M"),
    ]

    static func text(_ t0: TextObject, title: String, isNew: Bool, over window: NSWindow?) -> Outcome<TextObject>? {
        let dlg = Dialog(.textObject, title: title)
        let p = dlg.page
        p.setText(741, t0.text.replacingOccurrences(of: "\\n", with: "\n"))
        p.setItems(745, Lists.angles)
        p.setText(745, Num.g(t0.angle))
        p.setChecked(787, t0.backgroundMode == 2)
        p.setChecked(912, t0.absolutePosition)
        p.setMM(746, t0.x)
        p.setMM(747, t0.y)
        p.setItems(789, Lists.fontSizes)
        p.setText(789, Num.g(t0.latinFont.pointSize))
        p.setItems(742, Lists.latinFonts())
        p.setText(742, t0.latinFont.faceName)
        p.setItems(743, Lists.japaneseFonts())
        p.setText(743, t0.japaneseFont.faceName)
        p.setItems(788, Lists.fontStyles)
        p.select(788, (t0.latinFont.isItalic ? 1 : 0) + (t0.latinFont.isBold ? 2 : 0))
        p.setupColorPopup(790, color: t0.color)
        p.setItems(744, specialCharacters.map(\.0))
        p.setText(744, "")
        let justify = Int(t0.positionTail.first ?? "0") ?? 0
        for id in 908...910 { p.setChecked(id, id - 908 == justify) }
        p.on(744) {
            let i = p.selectedIndex(744)
            guard i >= 0, i < specialCharacters.count, let tv = p.textView(741) else { return }
            tv.insertText(specialCharacters[i].1, replacementRange: tv.selectedRange())
            p.setText(744, "")
            dlg.panel.makeFirstResponder(tv)
        }
        p.setEnabled(7, !isNew)
        dlg.buttons[748] = {
            HelpWindow.show(topic: .text)
            return false
        }
        dlg.buttons[797] = {
            if let s = NSPasteboard.general.string(forType: .string), let tv = p.textView(741) {
                tv.insertText(s, replacementRange: tv.selectedRange())
            }
            return false
        }
        dlg.buttons[557] = {
            AppSettings.shared.store(TitleDefaults(read(t0)), key: "title.\(t0.kind.rawValue)")
            MessageBox.show("この文字の設定(フォント・大きさ・色・向き)を既定にしました。")
            return false
        }
        dlg.buttons[7] = { true }

        func read(_ base: TextObject) -> TextObject {
            var t = base
            let raw = p.text(741).replacingOccurrences(of: "\r\n", with: "\n")
            t.text = raw.replacingOccurrences(of: "\n", with: "\\n")
            let angle = p.number(745, or: base.angle)
            t.backgroundMode = p.isChecked(787) ? 2 : 1
            t.absolutePosition = p.isChecked(912)
            t.x = p.mm(746, or: base.x)
            t.y = p.mm(747, or: base.y)
            let size = p.number(789, or: base.latinFont.pointSize)
            let latin = p.text(742).trimmingCharacters(in: .whitespaces)
            let jp = p.text(743).trimmingCharacters(in: .whitespaces)
            if !latin.isEmpty { t.latinFont.faceName = latin }
            if !jp.isEmpty { t.japaneseFont.faceName = jp }
            let style = max(p.selectedIndex(788), 0)
            for k in 0..<2 {
                var f = k == 0 ? t.latinFont : t.japaneseFont
                f.pointSize = max(size, 1)
                f.isItalic = style == 1 || style == 3
                f.isBold = style >= 2
                if k == 0 { t.latinFont = f } else { t.japaneseFont = f }
            }
            t.symbolFont.pointSize = max(size, 1)
            t.angle = angle
            t.color = p.popupColor(790, fallback: base.color)
            var tail = base.positionTail
            if tail.isEmpty { tail = ["0"] }
            tail[0] = String((908...910).first { p.isChecked($0) }.map { $0 - 908 } ?? 0)
            t.positionTail = tail
            return t
        }

        let r = dlg.run(over: window)
        switch r {
        case IDC.ok:
            let t = read(t0)
            return t.text.isEmpty ? (isNew ? nil : .delete) : (isNew ? .placeWithMouse(t) : .ok(t))
        case 7: return .delete
        default: return nil
        }
    }

    /// 「既定にする」で覚える文字の既定
    struct TitleDefaults: Codable {
        var latin: String, japanese: String, size: Double, style: Int, color: Int, angle: Double, back: Int
        init(_ t: TextObject) {
            latin = t.latinFont.faceName; japanese = t.japaneseFont.faceName; size = t.latinFont.pointSize
            style = (t.latinFont.isItalic ? 1 : 0) + (t.latinFont.isBold ? 2 : 0)
            color = t.color.colorref; angle = t.angle; back = t.backgroundMode
        }
        func apply(_ t: inout TextObject) {
            t.latinFont.faceName = latin; t.japaneseFont.faceName = japanese
            for k in 0..<2 {
                var f = k == 0 ? t.latinFont : t.japaneseFont
                f.pointSize = size; f.isItalic = style == 1 || style == 3; f.isBold = style >= 2
                if k == 0 { t.latinFont = f } else { t.japaneseFont = f }
            }
            t.symbolFont.pointSize = size
            t.color = SMPColor(colorref: color); t.angle = angle; t.backgroundMode = back
        }
    }

    // MARK: - 矢印(SET_ARROW)

    /// 形状の選択肢: (種類, 矢じりの付け方)
    static let arrowShapes: [(type: Int, head: Int, title: String)] = [
        (0, 1, "矢印(終点)"), (0, 2, "矢印(始点)"), (0, 3, "矢印(両端)"), (1, 1, "矢印2(終点)"), (1, 2, "矢印2(始点)"),
        (1, 3, "矢印2(両端)"), (2, 3, "エラーバー"), (0, 0, "線"),
    ]

    static func arrowImage(type: Int, head: Int) -> NSImage {
        NSImage(size: NSSize(width: 40, height: 13), flipped: true) { r in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return true }
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.setLineWidth(1)
            let y = r.midY, x0: CGFloat = 4, x1 = r.maxX - 4
            ctx.move(to: CGPoint(x: x0, y: y)); ctx.addLine(to: CGPoint(x: x1, y: y)); ctx.strokePath()
            if type == 2 {
                for x in [x0, x1] { ctx.move(to: CGPoint(x: x, y: y - 4)); ctx.addLine(to: CGPoint(x: x, y: y + 4)) }
                ctx.strokePath()
                return true
            }
            func headAt(_ x: CGFloat, _ dir: CGFloat) {
                let a = CGPoint(x: x - dir * 7, y: y - 3.5), b = CGPoint(x: x - dir * 7, y: y + 3.5)
                if type == 0 {
                    ctx.move(to: CGPoint(x: x, y: y)); ctx.addLine(to: a); ctx.addLine(to: b); ctx.closePath(); ctx.fillPath()
                } else {
                    ctx.move(to: a); ctx.addLine(to: CGPoint(x: x, y: y)); ctx.addLine(to: b); ctx.strokePath()
                }
            }
            if head & 1 != 0 { headAt(x1, 1) }
            if head & 2 != 0 { headAt(x0, -1) }
            return true
        }
    }

    static func arrow(_ s0: ShapeObject, isNew: Bool, over window: NSWindow?) -> Outcome<ShapeObject>? {
        let dlg = Dialog(.arrow)
        let p = dlg.page
        p.setMM(752, s0.length)
        p.setMM(751, s0.width)
        p.setColor(758, s0.color)
        p.setImageItems(702, Lists.lineTypeItems())
        p.select(702, max(0, min(s0.style, 5)))
        p.setMM(753, s0.pitch)
        func fillPositions(_ s: ShapeObject) {
            p.setNumber(754, s.x1); p.setNumber(755, s.y1)
            p.setNumber(756, s.x2); p.setNumber(757, s.y2)
        }
        fillPositions(s0)
        for id in 760...762 { p.setChecked(id, id - 760 == s0.xReference) }
        for id in 764...766 { p.setChecked(id, id - 764 == s0.yReference) }
        p.setImageItems(800, arrowShapes.map { ($0.title, arrowImage(type: $0.type, head: $0.head)) })
        p.select(800, arrowShapes.firstIndex { $0.type == s0.objectType && $0.head == s0.headMode }
                    ?? arrowShapes.firstIndex { $0.type == s0.objectType } ?? 0)
        p.setNumber(826, Double(s0.headOpen) / 100)
        p.setNumber(827, Double(s0.headClose) / 100)
        p.setEnabled(7, !isNew)
        dlg.buttons[797] = { true }
        dlg.buttons[718] = {
            AppSettings.shared.store(ShapeDefaults(read(s0)), key: "arrow")
            MessageBox.show("この矢印の設定を既定にしました。")
            return false
        }
        dlg.buttons[7] = { true }

        func read(_ base: ShapeObject) -> ShapeObject {
            var s = base
            s.length = p.mm(752, or: base.length)
            s.width = p.mm(751, or: base.width)
            s.color = p.color(758)
            s.style = max(p.selectedIndex(702), 0)
            s.pitch = max(p.mm(753, or: base.pitch), 1)
            s.x1 = p.number(754, or: base.x1); s.y1 = p.number(755, or: base.y1)
            s.x2 = p.number(756, or: base.x2); s.y2 = p.number(757, or: base.y2)
            s.xReference = (760...762).first { p.isChecked($0) }.map { $0 - 760 } ?? 0
            s.yReference = (764...766).first { p.isChecked($0) }.map { $0 - 764 } ?? 0
            let k = max(p.selectedIndex(800), 0)
            if k < arrowShapes.count {
                s.objectType = arrowShapes[k].type
                s.shapeType = arrowShapes[k].type
                s.headMode = arrowShapes[k].head
            }
            s.headOpen = Int((p.number(826, or: Double(base.headOpen) / 100) * 100).rounded())
            s.headClose = Int((p.number(827, or: Double(base.headClose) / 100) * 100).rounded())
            return s
        }
        switch dlg.run(over: window) {
        case IDC.ok: return .ok(read(s0))
        case 797: return .placeWithMouse(read(s0))
        case 7: return .delete
        default: return nil
        }
    }

    struct ShapeDefaults: Codable {
        var length: Int, width: Int, color: Int, style: Int, pitch: Int, type: Int, head: Int, open: Int, close: Int
        var shadow: Int, size: Int, aspect: Int
        init(_ s: ShapeObject) {
            length = s.length; width = s.width; color = s.color.colorref; style = s.style; pitch = s.pitch
            type = s.objectType; head = s.headMode; open = s.headOpen; close = s.headClose
            shadow = s.shadowColor.colorref; size = s.size; aspect = s.aspect
        }
        func apply(_ s: inout ShapeObject, arrow: Bool) {
            s.length = length; s.width = width; s.color = SMPColor(colorref: color); s.style = style; s.pitch = pitch
            if arrow { s.objectType = type; s.shapeType = type; s.headMode = head; s.headOpen = open; s.headClose = close }
            s.shadowColor = SMPColor(colorref: shadow); s.size = size; s.aspect = aspect
        }
    }

    // MARK: - 枠(SET_RECTANGLE)

    static func box(_ s0: ShapeObject, isNew: Bool, over window: NSWindow?) -> Outcome<ShapeObject>? {
        let dlg = Dialog(.box)
        let p = dlg.page
        p.setNumber(754, s0.x1); p.setNumber(755, s0.y1)
        p.setNumber(756, s0.x2); p.setNumber(757, s0.y2)
        p.setColor(708, s0.color)
        p.setColor(758, s0.shadowColor)
        p.setMM(752, s0.length)
        p.setMM(751, s0.width)
        p.setMM(787, s0.size)
        p.setMM(788, s0.aspect)
        p.setChecked(912, false)
        p.setEnabled(912, false)
        p.setEnabled(7, !isNew)
        dlg.buttons[797] = { true }
        dlg.buttons[718] = {
            AppSettings.shared.store(ShapeDefaults(read(s0)), key: "rect")
            MessageBox.show("この枠の設定を既定にしました。")
            return false
        }
        dlg.buttons[7] = { true }
        func read(_ base: ShapeObject) -> ShapeObject {
            var s = base
            s.x1 = p.number(754, or: base.x1); s.y1 = p.number(755, or: base.y1)
            s.x2 = p.number(756, or: base.x2); s.y2 = p.number(757, or: base.y2)
            s.color = p.color(708)
            s.shadowColor = p.color(758)
            s.length = max(p.mm(752, or: base.length), 0)
            s.width = max(p.mm(751, or: base.width), 0)
            s.size = max(p.mm(787, or: base.size), 0)
            s.aspect = max(p.mm(788, or: base.aspect), 0)
            return s
        }
        switch dlg.run(over: window) {
        case IDC.ok: return .ok(read(s0))
        case 797: return .placeWithMouse(read(s0))
        case 7: return .delete
        default: return nil
        }
    }

    // MARK: - Dot(SET_DOT)

    static func dot(_ d0: DotObject, isNew: Bool, over window: NSWindow?) -> Outcome<DotObject>? {
        let dlg = Dialog(.dot)
        let p = dlg.page
        let codes = PlotType.dotObjectCodes
        p.setImageItems(701, Lists.plotTypeItems(codes))
        p.select(701, codes.firstIndex(of: d0.dotType) ?? 0)
        p.setItems(702, Lists.dotLineStyles)
        p.select(702, max(0, min(d0.style, Lists.dotLineStyles.count - 1)))
        p.setColor(709, d0.color)
        p.setColor(719, d0.brushColor)
        p.setColor(708, d0.lineColor)
        p.setMM(717, d0.size)
        p.setMM(707, d0.width)
        p.setItems(778, DotBrush.titles)
        p.select(778, DotBrush.index(style: d0.brushStyle, hatch: d0.brushHatch))
        p.setMM(770, d0.pitch)
        p.setMM(746, d0.x)
        p.setMM(747, d0.y)
        let styleChanged = {
            // 線種が「なし」なら見本の線の長さ、ほかは区点の数
            if p.selectedIndex(702) <= 0 {
                p.setLabel(793, "線の長さ：")
                p.setMM(749, d0.length)
            } else {
                p.setLabel(793, "点の数：")
                p.setInteger(749, max(d0.pointCount, 1))
            }
        }
        p.on(702, styleChanged)
        styleChanged()
        p.setEnabled(7, !isNew)
        dlg.buttons[797] = { true }
        dlg.buttons[7] = { true }
        func read(_ base: DotObject) -> DotObject {
            var d = base
            let k = p.selectedIndex(701)
            if k >= 0 && k < codes.count { d.dotType = codes[k] }
            d.style = max(p.selectedIndex(702), 0)
            d.color = p.color(709)
            d.brushColor = p.color(719)
            d.lineColor = p.color(708)
            d.size = max(p.mm(717, or: base.size), 1)
            d.width = max(p.mm(707, or: base.width), 0)
            let b = DotBrush.values(index: max(p.selectedIndex(778), 0))
            d.brushStyle = b.style
            if b.style == 2 { d.brushHatch = b.hatch }
            d.pitch = max(p.mm(770, or: base.pitch), 1)
            d.x = p.mm(746, or: base.x)
            d.y = p.mm(747, or: base.y)
            if d.style == 0 { d.length = max(p.mm(749, or: base.length), 0) }
            return d
        }
        switch dlg.run(over: window) {
        case IDC.ok: return .ok(read(d0))
        case 797: return .placeWithMouse(read(d0))
        case 7: return .delete
        default: return nil
        }
    }

    // MARK: - 図(SET_GRAFILE)

    static func picture(_ pic0: PictureObject, isNew: Bool, imageSize: @escaping (String) -> CGSize?, over window: NSWindow?) -> Outcome<PictureObject>? {
        let dlg = Dialog(.picture)
        let p = dlg.page
        p.setText(741, pic0.path)
        p.setNumber(754, pic0.shape.x1)
        p.setNumber(755, pic0.shape.y1)
        p.setNumber(787, pic0.shape.x2 - pic0.shape.x1)
        p.setNumber(788, pic0.shape.y2 - pic0.shape.y1)
        p.setChecked(912, false)
        p.setEnabled(912, false)
        p.setEnabled(7, !isNew)
        func updateSize() {
            guard let size = imageSize(p.text(741)), size.width > 0 else {
                p.setLabel(778, ""); p.setLabel(779, ""); return
            }
            p.setLabel(778, "\(Int(size.width)) px")
            p.setLabel(779, "\(Int(size.height)) px")
            let w = p.number(787, or: 50)
            p.setText(788, Num.f2(w * size.height / size.width))
        }
        p.on(787) { updateSize() }
        updateSize()
        dlg.buttons[746] = {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.bmp, .png, .jpeg, .tiff, .gif, .pdf, .image]
            panel.message = "貼り付ける図(BMP・PNG・JPEG・PDF など)を選んでください。"
            if panel.runModal() == .OK, let url = panel.url {
                p.setText(741, url.path)
                if p.number(787) == nil || p.number(787) == 0 { p.setNumber(787, 50) }
                updateSize()
            }
            return false
        }
        dlg.buttons[7] = { true }
        dlg.validate = {
            if p.text(741).trimmingCharacters(in: .whitespaces).isEmpty { MessageBox.show("ファイル名を入れてください。"); return false }
            if imageSize(p.text(741)) == nil { MessageBox.show("その図は読めません: \(p.text(741))", style: .warning); return false }
            return true
        }
        switch dlg.run(over: window) {
        case IDC.ok:
            var pic = pic0
            pic.path = p.text(741)
            let w = p.number(787, or: 50), h = p.number(788, or: 50)
            pic.shape.x1 = p.number(754, or: pic0.shape.x1)
            pic.shape.y1 = p.number(755, or: pic0.shape.y1)
            pic.shape.x2 = pic.shape.x1 + w
            pic.shape.y2 = pic.shape.y1 + h
            if let size = imageSize(pic.path) { pic.info = [0, 0, Int(size.width), Int(size.height)] }
            return .ok(pic)
        case 7: return .delete
        default: return nil
        }
    }
}
