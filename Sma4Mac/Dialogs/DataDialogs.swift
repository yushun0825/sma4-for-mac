import AppKit
import Sma4Core

/// データメニューのダイアログ(Property・Data manager・File の選択・Data Mask・値を読む)
@MainActor
enum DataDialogs {

    // MARK: - データの設定(ファイル・点と線・読み込み・曲線)

    /// データのプロパティ。curvePage は最小二乗・スプライン・任意関数のとき 4 枚目(曲線)を付ける
    static func property(series s0: Series, index: Int, graph g: Graph, project: SMPProject, others: [Series],
                         over window: NSWindow?, startPage: Int = 0) -> Series? {
        var pages: [(String, DlgTemplate)] = [("ファイル", .dataFile), ("点と線", .dataLook), ("読み込み", .dataRead)]
        let hasCurve = s0.kind.hasCurve || s0.extensionAnalysis != nil
        if hasCurve { pages.append(("曲線", .lsqDraw)) }
        let sheet = PropertySheet(title: "データの設定", pages: pages, start: min(startPage, pages.count - 1))
        let p1 = sheet.page(0), p2 = sheet.page(1), p3 = sheet.page(2)
        let p4: TemplateView? = hasCurve ? sheet.page(3) : nil
        let file = project.dataFile(named: s0.name)
        for p in sheet.pages { p.setLabel(731, displayPath(s0)) }

        // ファイル
        let columns = max(columnCount(file, tabAsSpace: s0.tabAsSpace), 2)
        let columnItems = ["Numbering"] + (1...columns).map(String.init)
        p1.setItems(601, columnItems)
        p1.setItems(602, columnItems)
        p1.setItems(911, ["------------"])
        p1.select(911, 0)
        var errorX = s0.errorBarX, errorY = s0.errorBarY
        func fillPage1(_ s: Series) {
            p1.setChecked(793, s.visible)
            p1.setText(601, s.columnX < 0 ? "Numbering" : String(s.columnX + 1))
            p1.setText(602, s.columnY < 0 ? "Numbering" : String(s.columnY + 1))
            errorX = s.errorBarX
            errorY = s.errorBarY
            p1.setChecked(614, errorX == .plusPlus)
            p1.setChecked(787, errorX == .plusMinus)
            p1.setChecked(615, errorY == .plusPlus)
            p1.setChecked(788, errorY == .plusMinus)
        }
        // エラーバーは手動のラジオボタン: もう一度押すと外れる
        func errorButton(_ id: Int, _ x: Bool, _ value: Series.ErrorBar) {
            p1.on(id) {
                if x { errorX = errorX == value ? .none : value } else { errorY = errorY == value ? .none : value }
                p1.setChecked(614, errorX == .plusPlus)
                p1.setChecked(787, errorX == .plusMinus)
                p1.setChecked(615, errorY == .plusPlus)
                p1.setChecked(788, errorY == .plusMinus)
            }
        }
        errorButton(614, true, .plusPlus)
        errorButton(787, true, .plusMinus)
        errorButton(615, false, .plusPlus)
        errorButton(788, false, .plusMinus)
        let lines = file?.lines ?? []
        p1.setText(732, lines.prefix(300).joined(separator: "\n"))

        // 点と線
        let codes = PlotType.seriesCodes
        p2.setImageItems(701, Lists.plotTypeItems(codes))
        p2.setImageItems(702, Lists.lineTypeItems(includeFill: true))
        p2.setItems(778, DotBrush.titles)
        p2.setItems(704, ["x", "1240/x", "x*1000", "log(x)"])
        p2.setItems(706, ["y", "y*2", "-y", "log(y)", "y+#0003"])
        func fillPage2(_ s: Series) {
            p2.select(701, codes.firstIndex(of: s.dotType) ?? 0)
            p2.select(702, max(0, min(s.lineType.rawValue, 6)))
            p2.setColor(709, s.dotColor)
            p2.setColor(719, s.brushColor)
            p2.setColor(708, s.lineColor)
            p2.setMM(717, s.dotSize)
            p2.setMM(707, s.lineWidth)
            p2.setMM(770, s.pitch)
            p2.select(778, DotBrush.index(style: s.brushStyle, hatch: s.brushHatch))
            p2.setChecked(703, s.transformX)
            p2.setText(704, s.expressionX)
            p2.setChecked(705, s.transformY)
            p2.setText(706, s.expressionY)
        }
        // 高度
        func fillPage3(_ s: Series) {
            p3.setInteger(611, s.skipLines)
            p3.setInteger(612, s.maxLines)
            p3.setInteger(787, s.readStep)
            p3.setChecked(792, s.skipCommentCount)
            p3.setChecked(791, s.absoluteLineCount)
            p3.setChecked(790, s.tabAsSpace)
            p3.setInteger(788, s.horizontalAverage)
            p3.setInteger(789, s.verticalAverage)
            p3.setNumber(793, s.barBase)
            p3.setChecked(711, !s.useUAxis)
            p3.setChecked(712, s.useUAxis)
            p3.setChecked(714, !s.useRAxis)
            p3.setChecked(715, s.useRAxis)
        }
        p3.setEnabled(712, g.uIndependent)
        p3.setEnabled(715, g.rIndependent)
        if let p4 { CurvePage.fill(p4, s0) }
        fillPage1(s0)
        fillPage2(s0)
        fillPage3(s0)

        // 見本
        let sample = p2.sample(794)
        let redraw = {
            let s = read(s0)
            sample?.drawer = { ctx, r in SeriesSample.draw(s, in: r, ctx: ctx) }
        }
        p2.onAnyChange = redraw

        func read(_ base: Series) -> Series {
            var s = base
            s.visible = p1.isChecked(793)
            s.columnX = parseColumn(p1.text(601), fallback: base.columnX)
            s.columnY = parseColumn(p1.text(602), fallback: base.columnY)
            s.errorBarX = errorX
            s.errorBarY = errorY
            let ci = p2.selectedIndex(701)
            if ci >= 0 && ci < codes.count { s.dotType = codes[ci] }
            s.lineType = LineType(code: max(p2.selectedIndex(702), 0))
            s.dotColor = p2.color(709)
            s.brushColor = p2.color(719)
            s.lineColor = p2.color(708)
            s.dotSize = max(p2.mm(717, or: base.dotSize), 1)
            s.lineWidth = max(p2.mm(707, or: base.lineWidth), 0)
            s.pitch = max(p2.mm(770, or: base.pitch), 1)
            let b = DotBrush.values(index: max(p2.selectedIndex(778), 0))
            s.brushStyle = b.style
            if b.style == 2 { s.brushHatch = b.hatch }
            s.transformX = p2.isChecked(703)
            s.expressionX = p2.text(704).trimmingCharacters(in: .whitespaces).isEmpty ? "x" : p2.text(704)
            s.transformY = p2.isChecked(705)
            s.expressionY = p2.text(706).trimmingCharacters(in: .whitespaces).isEmpty ? "y" : p2.text(706)
            s.skipLines = max(p3.integer(611, or: base.skipLines), 0)
            s.maxLines = p3.integer(612, or: base.maxLines)
            s.readStep = max(p3.integer(787, or: base.readStep), 1)
            s.skipCommentCount = p3.isChecked(792)
            s.absoluteLineCount = p3.isChecked(791)
            s.tabAsSpace = p3.isChecked(790)
            s.horizontalAverage = max(p3.integer(788, or: base.horizontalAverage), 0)
            s.verticalAverage = max(p3.integer(789, or: base.verticalAverage), 0)
            s.barBase = p3.number(793, or: base.barBase)
            s.useUAxis = p3.isChecked(712)
            s.useRAxis = p3.isChecked(715)
            if let p4 { CurvePage.read(p4, into: &s) }
            return s
        }
        redraw()

        // 共通保存(V)・保存・参照(B)
        let ext = (s0.name as NSString).pathExtension.lowercased()
        for p in [p1, p2, p3] {
            p.on(557) {
                SeriesDefaults.save(read(s0), key: "data.default")
                MessageBox.show("このページの設定を、データファイルを開くときの既定にしました。")
            }
            p.on(558) {
                SeriesDefaults.save(read(s0), key: "data.ext." + ext)
                MessageBox.show("このページの設定を、拡張子 .\(ext.isEmpty ? "(なし)" : ext) のファイルの既定にしました。")
            }
            p.on(559) {
                let names = others.map { $0.displayName }
                guard !names.isEmpty, let k = ListDialogs.chooseOne(title: "参照するファイル", items: names, over: sheet.panel),
                      k < others.count else { return }
                var s = others[k]
                s.name = s0.name; s.path = s0.path; s.kind = s0.kind; s.kindRaw = s0.kindRaw
                fillPage1(s); fillPage2(s); fillPage3(s)
                redraw()
            }
        }
        if let p4 {
            p4.on(557) {
                CurvePage.saveDefaults(p4)
                MessageBox.show("描画条件を既定にしました。")
            }
        }

        sheet.validate = {
            let s = read(s0)
            for (on, text) in [(s.transformX, s.expressionX), (s.transformY, s.expressionY)] where on {
                do { _ = try Expression(text) } catch {
                    MessageBox.show("数式が正しくありません: \(text)\n\((error as? ExpressionError)?.message ?? "")", style: .warning)
                    return false
                }
            }
            return true
        }
        guard sheet.run(over: window) == IDC.ok else { return nil }
        return read(s0)
    }

    static func displayPath(_ s: Series) -> String {
        s.path.isEmpty ? s.name : s.path
    }

    static func parseColumn(_ text: String, fallback: Int) -> Int {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.lowercased().hasPrefix("num") { return -1 }
        if let n = Int(t), n >= 1 { return n - 1 }
        return fallback
    }

    static func columnCount(_ file: DataFile?, tabAsSpace: Bool) -> Int {
        guard let file else { return 2 }
        var m = 0
        for line in file.lines.prefix(200) {
            if case .values(let v) = DataParser.parse(line: line, tabAsSpace: tabAsSpace) { m = max(m, v.count) }
        }
        return m
    }

    // MARK: - Data manager

    struct ManagerResult { var series: [Series]; var propertyIndex: Int? }

    /// Update・データファイルを閉じる: 並べ替え・閉じる・プロパティ
    static func manager(series: [Series], title: String = "データの管理", okTitle: String = "設定…", over window: NSWindow?) -> ManagerResult? {
        let dlg = Dialog(.dataManager, title: title)
        let p = dlg.page
        var list = series
        p.setText(IDC.ok, okTitle)
        guard let lb = p.list(561) else { return nil }
        func reload(select: IndexSet = []) {
            lb.items = list.map(managerTitle)
            lb.selectedIndexes = select
        }
        lb.drawRow = { i, rect, selected in
            guard i < list.count else { return }
            ManagerRow.draw(list[i], text: managerTitle(list[i]), in: rect, selected: selected)
        }
        reload(select: list.isEmpty ? [] : [0])
        lb.onDoubleClick = { _ in dlg.end(IDC.ok) }
        dlg.buttons[787] = {  // 上: 最初に描く
            let sel = lb.selectedIndexes
            let moving = sel.map { list[$0] }
            for i in sel.reversed() { list.remove(at: i) }
            list.insert(contentsOf: moving, at: 0)
            reload(select: IndexSet(0..<moving.count))
            return false
        }
        dlg.buttons[788] = {  // 下: 最後に描く
            let sel = lb.selectedIndexes
            let moving = sel.map { list[$0] }
            for i in sel.reversed() { list.remove(at: i) }
            list.append(contentsOf: moving)
            reload(select: IndexSet((list.count - moving.count)..<list.count))
            return false
        }
        dlg.buttons[789] = {  // Close: 選んだファイルを閉じる
            let sel = lb.selectedIndexes
            guard !sel.isEmpty else { return false }
            for i in sel.reversed() { list.remove(at: i) }
            reload()
            return false
        }
        dlg.buttons[768] = {  // All
            lb.selectedIndexes = IndexSet(0..<list.count)
            return false
        }
        guard dlg.run(over: window) == IDC.ok else { return nil }
        let sel = lb.selectedIndexes
        return ManagerResult(series: list, propertyIndex: sel.count == 1 ? sel.first : nil)
    }

    static func managerTitle(_ s: Series) -> String {
        s.displayName + kindSuffix(s)
    }

    /// データの管理で名前の後ろに付く印
    static func kindSuffix(_ s: Series) -> String {
        if let a = s.extensionAnalysis { return " (\(a.menuTitle))" }
        switch s.kind {
        case .polynomialLSQ: return " (F多項式)"
        case .expLSQ: return " (F指数)"
        case .logLSQ: return " (F対数)"
        case .powerLSQ: return " (Fべき)"
        case .generalLSQ: return " (F一般)"
        case .spline:
            switch s.lsqOrder { case 0: return " (SPL～S)"; case 1: return " (SPL～P)"; case 2: return " (SPL 〇)"; default: return " (SPL ? )" }
        case .function: return " (CAL)"
        default: return ""
        }
    }

    // MARK: - Data Mask の選択

    enum MaskChoice { case new, delete(Int) }

    static func maskChoice(masks: [DataMask], names: [String], over window: NSWindow?) -> MaskChoice? {
        let dlg = Dialog(.maskChoice)
        let p = dlg.page
        let items = masks.map { m -> String in
            let n = m.seriesIndex < names.count ? names[m.seriesIndex] : "?"
            return String(format: "%@: %10g %10g, %10g %10g", n, m.xMin, m.xMax, m.yMin, m.yMax)
        }
        p.list(561)?.items = items
        p.list(561)?.selectedIndexes = items.isEmpty ? [] : [0]
        dlg.buttons[767] = { true }
        let r = dlg.run(over: window)
        if r == 767 { return .new }
        if r == IDC.ok, let i = p.list(561)?.selectedIndexes.first { return .delete(i) }
        return nil
    }

    // MARK: - Save Data の区切り

    /// 保存の窓の下に「タブで区切る・カンマで区切る」を付ける
    static func separatorAccessory(tab: Bool) -> (NSView, () -> Bool) {
        let v = TemplateView(.separatorChoice)
        v.setChecked(787, tab)
        v.setChecked(788, !tab)
        return (v, { v.isChecked(787) })
    }
}

/// 曲線(描画条件)のページ: 連続データの範囲・分割数・線
@MainActor
enum CurvePage {
    static func fill(_ p: TemplateView, _ s: Series) {
        p.setNumber(513, s.curveStart)
        p.setNumber(514, s.curveEnd)
        p.setInteger(515, s.curveDivisions)
        p.setImageItems(677, Lists.lineTypeItems())
        p.select(677, max(0, min(s.curveLineType.rawValue, 5)))
        p.setChecked(793, s.considerOutOfRange)
        for id in 517...519 { p.setChecked(id, id - 517 == s.curveSpacing.rawValue) }
        p.setMM(675, s.curveWidth)
        p.setMM(770, s.curvePitch)
        p.setColor(676, s.curveColor)
    }

    static func read(_ p: TemplateView, into s: inout Series) {
        s.curveStart = p.number(513, or: s.curveStart)
        s.curveEnd = p.number(514, or: s.curveEnd)
        s.curveDivisions = max(min(p.integer(515, or: s.curveDivisions), 3999), 1)
        s.curveLineType = LineType(code: max(p.selectedIndex(677), 0))
        s.considerOutOfRange = p.isChecked(793)
        s.curveSpacing = Series.CurveSpacing(rawValue: (517...519).first { p.isChecked($0) }.map { $0 - 517 } ?? 0) ?? .linear
        s.curveWidth = max(p.mm(675, or: s.curveWidth), 0)
        s.curvePitch = max(p.mm(770, or: s.curvePitch), 1)
        s.curveColor = p.color(676)
    }

    struct Defaults: Codable { var divisions: Int; var lineType: Int; var width: Int; var pitch: Int; var color: Int; var outside: Bool }

    static func saveDefaults(_ p: TemplateView) {
        var s = Series(name: "")
        read(p, into: &s)
        AppSettings.shared.store(Defaults(divisions: s.curveDivisions, lineType: s.curveLineType.rawValue, width: s.curveWidth,
                                          pitch: s.curvePitch, color: s.curveColor.colorref, outside: s.considerOutOfRange),
                                 key: "curve.default")
    }

    static func applyDefaults(_ s: inout Series) {
        guard let d = AppSettings.shared.stored("curve.default", as: Defaults.self) else { return }
        s.curveDivisions = d.divisions
        s.curveLineType = LineType(code: d.lineType)
        s.curveWidth = d.width
        s.curvePitch = d.pitch
        s.curveColor = SMPColor(colorref: d.color)
        s.considerOutOfRange = d.outside
    }
}

/// データファイルを開くときの既定(「全体の既定にする」「拡張子の既定にする」で覚える)
struct SeriesDefaults: Codable {
    var errorX: Int, errorY: Int, columnX: Int, columnY: Int
    var lineWidth: Int, lineColor: Int, pitch: Int, lineType: Int
    var dotType: Int, dotSize: Int, dotColor: Int, brushStyle: Int, brushColor: Int, brushHatch: Int
    var transformX: Bool, transformY: Bool, expressionX: String, expressionY: String
    var skip: Int, maxLines: Int, step: Int, skipComment: Bool, absolute: Bool, tabAsSpace: Bool
    var hAvg: Int, vAvg: Int, barBase: Double

    @MainActor
    static func save(_ s: Series, key: String) {
        let d = SeriesDefaults(errorX: s.errorBarX.rawValue, errorY: s.errorBarY.rawValue, columnX: s.columnX, columnY: s.columnY,
                               lineWidth: s.lineWidth, lineColor: s.lineColor.colorref, pitch: s.pitch, lineType: s.lineType.rawValue,
                               dotType: s.dotType, dotSize: s.dotSize, dotColor: s.dotColor.colorref, brushStyle: s.brushStyle,
                               brushColor: s.brushColor.colorref, brushHatch: s.brushHatch, transformX: s.transformX,
                               transformY: s.transformY, expressionX: s.expressionX, expressionY: s.expressionY,
                               skip: s.skipLines, maxLines: s.maxLines, step: s.readStep, skipComment: s.skipCommentCount,
                               absolute: s.absoluteLineCount, tabAsSpace: s.tabAsSpace, hAvg: s.horizontalAverage,
                               vAvg: s.verticalAverage, barBase: s.barBase)
        AppSettings.shared.store(d, key: key)
    }

    /// 拡張子ごとの既定 → 共通の既定 の順に当てる
    @MainActor
    static func apply(to s: inout Series, fileName: String) {
        let ext = (fileName as NSString).pathExtension.lowercased()
        guard let d = AppSettings.shared.stored("data.ext." + ext, as: SeriesDefaults.self)
                ?? AppSettings.shared.stored("data.default", as: SeriesDefaults.self) else { return }
        s.errorBarX = Series.ErrorBar(rawValue: d.errorX) ?? .none
        s.errorBarY = Series.ErrorBar(rawValue: d.errorY) ?? .none
        s.columnX = d.columnX; s.columnY = d.columnY
        s.lineWidth = d.lineWidth; s.lineColor = SMPColor(colorref: d.lineColor); s.pitch = d.pitch
        s.lineType = LineType(code: d.lineType)
        s.dotType = d.dotType; s.dotSize = d.dotSize; s.dotColor = SMPColor(colorref: d.dotColor)
        s.brushStyle = d.brushStyle; s.brushColor = SMPColor(colorref: d.brushColor); s.brushHatch = d.brushHatch
        s.transformX = d.transformX; s.transformY = d.transformY; s.expressionX = d.expressionX; s.expressionY = d.expressionY
        s.skipLines = d.skip; s.maxLines = d.maxLines; s.readStep = d.step; s.skipCommentCount = d.skipComment
        s.absoluteLineCount = d.absolute; s.tabAsSpace = d.tabAsSpace; s.horizontalAverage = d.hAvg; s.verticalAverage = d.vAvg
        s.barBase = d.barBase
    }
}

/// 系列の見本(プロットの見本の枠・データマネージャの行・凡例の見本)
@MainActor
enum SeriesSample {
    /// 0.01 mm → 見本の点(100% 表示と同じ大きさ)
    static func pt(_ v: Int) -> CGFloat { CGFloat(v) / 100 * CanvasView.pointsPerMM }

    static func draw(_ s: Series, in r: CGRect, ctx: CGContext, lineLength: CGFloat? = nil) {
        let y = r.midY
        let len = lineLength ?? r.width - 12
        let x0 = r.midX - len / 2, x1 = r.midX + len / 2
        if s.lineType != .none {
            ctx.setStrokeColor(s.lineColor.cgColor)
            ctx.setLineWidth(max(pt(s.lineWidth), 0.5))
            let d = GraphRenderer.dash(s.lineType.rawValue, pitch: s.pitch, width: s.lineWidth).map { CGFloat($0) / 100 * CanvasView.pointsPerMM }
            ctx.setLineDash(phase: 0, lengths: d)
            ctx.move(to: CGPoint(x: x0, y: y)); ctx.addLine(to: CGPoint(x: x1, y: y))
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }
        if s.dotType != 0 {
            GraphRenderer.drawPlotMark(code: s.dotType, center: CGPoint(x: r.midX, y: y), diameter: max(pt(s.dotSize), 3),
                                       dotColor: s.dotColor, lineWidth: max(pt(s.lineWidth), 0.5), brushStyle: s.brushStyle,
                                       brushColor: s.brushColor, brushHatch: s.brushHatch, in: ctx)
        }
    }
}

/// データの管理の 1 行(点の見本・線の見本・名前)
@MainActor
enum ManagerRow {
    static func draw(_ s: Series, text: String, in rect: NSRect, selected: Bool) {
        if selected {
            NSColor.selectedContentBackgroundColor.setFill()
            rect.fill()
        }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        var sample = s
        sample.dotSize = min(s.dotSize, 250)
        sample.lineWidth = min(s.lineWidth, 40)
        ctx.saveGState()
        SeriesSample.draw(sample, in: CGRect(x: rect.minX + 2, y: rect.minY, width: 44, height: rect.height), ctx: ctx, lineLength: 40)
        ctx.restoreGState()
        let attrs: [NSAttributedString.Key: Any] = [.font: TemplateView.font,
                                                     .foregroundColor: selected ? NSColor.alternateSelectedControlTextColor : NSColor.labelColor]
        (text as NSString).draw(at: NSPoint(x: rect.minX + 50, y: rect.minY + 1), withAttributes: attrs)
    }
}

/// File の選択(LISTDIALOG・LISTDIALOG2)と入力(MY_INPUTDIALOG)
@MainActor
enum ListDialogs {
    /// 1 つ選ぶ(LISTDIALOG2)。newButton なら「新規」を押したとき -1
    static func chooseOne(title: String, items: [String], allowNew: Bool = false, initial: Int = 0, over window: NSWindow?) -> Int? {
        if items.count == 1 && !allowNew { return 0 }
        let dlg = Dialog(.chooseOne, title: title)
        let p = dlg.page
        p.list(561)?.items = items
        p.list(561)?.selectedIndexes = items.isEmpty ? [] : [max(0, min(initial, items.count - 1))]
        p.list(561)?.onDoubleClick = { _ in dlg.end(IDC.ok) }
        p.setEnabled(767, allowNew)
        dlg.buttons[767] = { true }
        let r = dlg.run(over: window)
        if r == 767 { return -1 }
        guard r == IDC.ok, let i = p.list(561)?.selectedIndexes.first else { return nil }
        return i
    }

    /// いくつか選ぶ(LISTDIALOG: All あり)
    static func chooseMany(title: String, items: [String], selected: IndexSet, allowNew: Bool = false, over window: NSWindow?) -> IndexSet? {
        let dlg = Dialog(.chooseMany, title: title)
        let p = dlg.page
        p.list(561)?.items = items
        p.list(561)?.selectedIndexes = selected
        p.setEnabled(767, allowNew)
        dlg.buttons[767] = { true }
        dlg.buttons[768] = {
            p.list(561)?.selectedIndexes = IndexSet(0..<items.count)
            return false
        }
        let r = dlg.run(over: window)
        guard r == IDC.ok else { return nil }
        return p.list(561)?.selectedIndexes ?? []
    }

    /// 1 行の入力(MY_INPUTDIALOG)
    static func input(title: String, prompt: String, text: String, over window: NSWindow?) -> String? {
        let dlg = Dialog(.input, title: title)
        dlg.page.setLabel(901, prompt)
        dlg.page.setText(902, text)
        guard dlg.run(over: window) == IDC.ok else { return nil }
        return dlg.page.text(902)
    }
}
