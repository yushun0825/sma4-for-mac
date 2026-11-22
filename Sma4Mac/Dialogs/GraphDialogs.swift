import AppKit
import Sma4Core

/// グラフメニューのダイアログ(X-Axis・Frame・グラフのプロパティ・トリミング)と用紙設定・図面コピーの領域
@MainActor
enum GraphDialogs {
    static let axisCaptions = ["X軸", "Y軸", "U軸", "R軸"]
    static let commonTitles = ["U軸も同じ", "R軸も同じ", "X軸も同じ", "Y軸も同じ"]
    static let crossItems = ["おまかせ", "最小", "最大"]

    // MARK: - X・Y・U・R 軸(範囲・目盛・数字)

    static func axis(_ index: Int, graph g0: Graph, over window: NSWindow?, startPage: Int = 0) -> Graph? {
        let sheet = PropertySheet(title: axisCaptions[index],
                                  pages: [("範囲", .axisScale), ("目盛", .axisTicks), ("数字", .axisNumbers)],
                                  start: startPage)
        let p1 = sheet.page(0), p2 = sheet.page(1), p3 = sheet.page(2)
        let a = g0.axes[index]
        let base = index % 2  // X・U → X、Y・R → Y

        // 範囲
        p1.setChecked(524, a.drawAxis)
        p1.setNumber(513, a.from)
        p1.setNumber(514, a.to)
        p1.setChecked(511, a.autoStep)
        p1.setNumber(515, a.increment)
        p1.setInteger(516, a.division)
        for id in 517...521 { p1.setChecked(id, id - 517 == a.scaleType.rawValue) }
        p1.setText(512, commonTitles[index])
        p1.setChecked(512, g0.axes[base].commonWithOpposite)
        p1.setEnabled(512, g0.frameType == .box)
        // 他のグラフとのリンクと目盛変換はまだ使えない
        p1.setEnabled(793, false)
        p1.setEnabled(794, false)
        p1.setEnabled(795, false)
        let autoChanged = {
            let on = p1.isChecked(511)
            p1.setEnabled(515, !on)
            p1.setEnabled(516, !on)
        }
        p1.on(511, autoChanged)
        autoChanged()

        // 目盛
        let tickRows: [(TickStyle, ids: (inside: Int, outside: Int, color: Int, width: Int, style: Int, pitch: Int, length: Int))] = [
            (a.major, (525, 527, 536, 529, 798, 533, 531)),
            (a.minor, (526, 528, 537, 530, 799, 534, 532)),
        ]
        for (t, ids) in tickRows {
            p2.setChecked(ids.inside, t.inside)
            p2.setChecked(ids.outside, t.outside)
            p2.setColor(ids.color, t.color)
            p2.setMM(ids.width, t.width)
            p2.setItems(ids.style, Lists.lineTypes)
            p2.select(ids.style, max(0, min(t.style, Lists.lineTypes.count - 1)))
            p2.setMM(ids.pitch, t.pitch)
            p2.setMM(ids.length, t.length)
        }
        p2.setChecked(551, a.limitRange)
        p2.setNumber(541, Double(a.limitStart) / 100)
        p2.setNumber(542, Double(a.limitEnd) / 100)
        let limitChanged = {
            p2.setEnabled(541, p2.isChecked(551))
            p2.setEnabled(542, p2.isChecked(551))
        }
        p2.on(551, limitChanged)
        limitChanged()
        p2.setItems(544, crossItems)
        p2.select(544, a.crossPosition < 0 ? 0 : (a.crossPosition >= 10000 ? 2 : 1))
        p2.setEnabled(544, g0.frameType == .axes)

        // 数字
        p3.setChecked(538, a.drawLabels)
        p3.setChecked(548, g0.zeroCommon)
        p3.setChecked(547, a.zeroAsInteger)
        p3.setChecked(546, a.zeroPadding)
        p3.setChecked(545, a.plusSign)
        p3.setChecked(549, a.drawGetta)
        p3.setEnabled(550, false)
        p3.setItems(742, Lists.latinFonts())
        p3.setText(742, a.font.faceName)
        p3.setupColorPopup(790, color: a.labelColor)
        p3.setItems(788, Lists.fontStyles)
        p3.select(788, (a.font.isItalic ? 1 : 0) + (a.font.isBold ? 2 : 0))
        p3.setItems(789, Lists.fontSizes)
        p3.setText(789, Num.g(a.font.pointSize))
        p3.setMM(539, a.labelShiftX)
        p3.setMM(540, a.labelShiftY)
        p3.setInteger(541, a.labelStart)
        p3.setInteger(542, a.labelCount)
        p3.setInteger(543, a.labelInterval)
        let digits = (0...10).map(String.init)
        p3.setItems(798, digits)
        p3.select(798, max(0, min(a.integerDigits, 10)))
        p3.setItems(799, digits)
        p3.select(799, max(0, min(a.decimalDigits, 10)))

        sheet.validate = {
            guard let from = p1.number(513), let to = p1.number(514), from.isFinite, to.isFinite else {
                MessageBox.show("From・To に数を入れてください。", style: .warning); return false
            }
            if from == to { MessageBox.show("From と To が同じです。", style: .warning); return false }
            let type = (517...521).first { p1.isChecked($0) }.map { $0 - 517 } ?? 0
            if ScaleType(rawValue: type)?.isLog == true && (from <= 0 || to <= 0) {
                MessageBox.show("Log10 の軸では From・To を正の数にしてください。", style: .warning); return false
            }
            return true
        }
        guard sheet.run(over: window) == IDC.ok else { return nil }

        var g = g0
        var n = a
        n.drawAxis = p1.isChecked(524)
        n.from = p1.number(513, or: a.from)
        n.to = p1.number(514, or: a.to)
        n.autoStep = p1.isChecked(511)
        n.increment = p1.number(515, or: a.increment)
        n.division = max(p1.integer(516, or: a.division), 1)
        n.scaleType = ScaleType(rawValue: (517...521).first { p1.isChecked($0) }.map { $0 - 517 } ?? 0) ?? .linear
        if n.autoStep || n.increment == 0 {
            let auto = AxisScale.autoScaled(n, minValue: min(n.from, n.to), maxValue: max(n.from, n.to))
            n.increment = auto.increment
            n.division = auto.division
            if n.to < n.from { n.increment = abs(n.increment) }
        }
        if n.scaleType.isLog {
            let allowed: [Double] = [1, 2, 3, 4, 5, 10]
            if !allowed.contains(n.increment) { n.increment = 10 }
            if n.division != 1 && n.division != 10 { n.division = 10 }
        }
        func tick(_ old: TickStyle, _ ids: (inside: Int, outside: Int, color: Int, width: Int, style: Int, pitch: Int, length: Int)) -> TickStyle {
            var t = old
            t.inside = p2.isChecked(ids.inside)
            t.outside = p2.isChecked(ids.outside)
            t.color = p2.color(ids.color)
            t.width = p2.mm(ids.width, or: old.width)
            t.style = max(p2.selectedIndex(ids.style), 0)
            t.pitch = p2.mm(ids.pitch, or: old.pitch)
            t.length = p2.mm(ids.length, or: old.length)
            return t
        }
        n.major = tick(a.major, tickRows[0].ids)
        n.minor = tick(a.minor, tickRows[1].ids)
        n.limitRange = p2.isChecked(551)
        n.limitStart = Int((p2.number(541, or: Double(a.limitStart) / 100) * 100).rounded())
        n.limitEnd = Int((p2.number(542, or: Double(a.limitEnd) / 100) * 100).rounded())
        switch p2.selectedIndex(544) {
        case 1: n.crossPosition = 0
        case 2: n.crossPosition = 10000
        default: n.crossPosition = -1
        }
        n.drawLabels = p3.isChecked(538)
        n.zeroAsInteger = p3.isChecked(547)
        n.zeroPadding = p3.isChecked(546)
        n.plusSign = p3.isChecked(545)
        n.drawGetta = p3.isChecked(549)
        let face = p3.text(742).trimmingCharacters(in: .whitespaces)
        if !face.isEmpty { n.font.faceName = face }
        let style = max(p3.selectedIndex(788), 0)
        n.font.isItalic = style == 1 || style == 3
        n.font.isBold = style >= 2
        if let pt = p3.number(789), pt > 0 { n.font.pointSize = pt }
        n.labelColor = p3.popupColor(790, fallback: a.labelColor)
        n.labelShiftX = p3.mm(539, or: a.labelShiftX)
        n.labelShiftY = p3.mm(540, or: a.labelShiftY)
        n.labelStart = p3.integer(541, or: a.labelStart)
        n.labelCount = p3.integer(542, or: a.labelCount)
        n.labelInterval = max(p3.integer(543, or: a.labelInterval), 1)
        n.integerDigits = max(p3.selectedIndex(798), 0)
        n.decimalDigits = max(p3.selectedIndex(799), 0)

        let common = p1.isChecked(512)
        g.axes[index] = n
        g.zeroCommon = p3.isChecked(548)
        g.axes[base].commonWithOpposite = common
        g.axes[base + 2].commonWithOpposite = common
        // 共通なら U・R は X・Y と同じ値にしておく(SMP の書き方)
        if common {
            if index < 2 { g.axes[index + 2] = mirrored(g.axes[index], from: g.axes[index + 2]) }
            else { g.axes[base] = mirrored(g.axes[index], from: g.axes[base]); g.axes[base].commonWithOpposite = true }
        }
        return g
    }

    static func mirrored(_ a: AxisSpec, from old: AxisSpec) -> AxisSpec {
        var m = a
        m.drawLabels = old.drawLabels
        m.line2Tail = old.line2Tail
        m.labelShiftX = old.labelShiftX
        m.labelShiftY = old.labelShiftY
        return m
    }

    // MARK: - Frame・グラフのプロパティ(Graph Property: Frame・Title・Scale)

    static func graphProperty(graph g0: Graph, over window: NSWindow?, startPage: Int) -> Graph? {
        let sheet = PropertySheet(title: "グラフの設定",
                                  pages: [("枠", .graphFrame), ("名前", .graphTitle), ("範囲", .graphRanges)],
                                  start: startPage)
        let p1 = sheet.page(0), p2 = sheet.page(1), p3 = sheet.page(2)
        p1.setMM(501, g0.left)
        p1.setMM(502, g0.top)
        p1.setMM(503, g0.width)
        p1.setMM(504, g0.height)
        p1.setMM(505, g0.frameWidth)
        p1.setColor(523, g0.frameColor)
        p1.setColor(708, g0.background)
        for id in 506...509 { p1.setChecked(id, id - 506 == g0.frameType.rawValue) }

        p2.setText(787, g0.name)
        p2.setText(788, g0.comment)
        p2.setInteger(789, g0.zoom)
        p2.setEnabled(790, false)

        let rows: [(check: Int, lo: Int, hi: Int, axis: Int)] = [(778, 787, 788, 0), (779, 789, 790, 1), (780, 791, 792, 2), (781, 793, 794, 3)]
        for r in rows {
            let ax = g0.effectiveAxis(r.axis)
            p3.setNumber(r.lo, ax.from)
            p3.setNumber(r.hi, ax.to)
            let available = r.axis < 2 || (r.axis == 2 ? g0.uIndependent : g0.rIndependent)
            p3.setChecked(r.check, false)
            p3.setEnabled(r.check, available)
            let update = {
                p3.setEnabled(r.lo, p3.isChecked(r.check))
                p3.setEnabled(r.hi, p3.isChecked(r.check))
            }
            p3.on(r.check, update)
            update()
        }

        sheet.validate = {
            for id in 501...505 where p1.number(id) == nil {
                MessageBox.show("数を入れてください。", style: .warning); _ = id; return false
            }
            if (p1.number(503) ?? 0) <= 0 || (p1.number(504) ?? 0) <= 0 {
                MessageBox.show("幅と高さは正の数にしてください。", style: .warning); return false
            }
            if (p2.number(789) ?? 0) <= 0 { MessageBox.show("Zoom は正の数にしてください。", style: .warning); return false }
            return true
        }
        guard sheet.run(over: window) == IDC.ok else { return nil }

        var g = g0
        g.left = p1.mm(501, or: g0.left)
        g.top = p1.mm(502, or: g0.top)
        g.width = max(p1.mm(503, or: g0.width), 100)
        g.height = max(p1.mm(504, or: g0.height), 100)
        g.frameWidth = p1.mm(505, or: g0.frameWidth)
        g.frameColor = p1.color(523)
        g.background = p1.color(708)
        g.frameType = FrameType(rawValue: (506...509).first { p1.isChecked($0) }.map { $0 - 506 } ?? 1) ?? .box
        let name = p2.text(787).trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { g.name = name }
        g.comment = p2.text(788)
        // 等倍設定: 右マージン・上マージンを保ったまま大きさを変える
        let newZoom = max(p2.integer(789, or: g0.zoom), 1)
        if newZoom != g0.zoom {
            let right = g.left + Int(Double(g.width) * g0.zoomFactor)
            g.zoom = newZoom
            g.left = right - Int(Double(g.width) * g.zoomFactor)
        }
        for r in rows where p3.isChecked(r.check) {
            g.axes[r.axis].from = p3.number(r.lo, or: g.axes[r.axis].from)
            g.axes[r.axis].to = p3.number(r.hi, or: g.axes[r.axis].to)
            if g.axes[r.axis].autoStep {
                let a = AxisScale.autoScaled(g.axes[r.axis], minValue: min(g.axes[r.axis].from, g.axes[r.axis].to),
                                             maxValue: max(g.axes[r.axis].from, g.axes[r.axis].to))
                g.axes[r.axis].increment = a.increment
                g.axes[r.axis].division = a.division
            }
            if r.axis < 2 && g.axes[r.axis].commonWithOpposite {
                g.axes[r.axis + 2] = mirrored(g.axes[r.axis], from: g.axes[r.axis + 2])
            }
        }
        return g
    }

    // MARK: - トリミング(スケールの設定)

    /// ranges: 軸ごとの (使う, 最小, 最大)
    static func trimming(ranges: [(Bool, Double, Double)], over window: NSWindow?) -> [(Bool, Double, Double)]? {
        let dlg = Dialog(.trimming)
        let p = dlg.page
        let rows: [(check: Int, lo: Int, hi: Int)] = [(778, 787, 788), (779, 789, 790), (780, 791, 792), (781, 793, 794)]
        for (k, r) in rows.enumerated() where k < ranges.count {
            p.setChecked(r.check, ranges[k].0)
            p.setNumber(r.lo, ranges[k].1)
            p.setNumber(r.hi, ranges[k].2)
            let update = { p.setEnabled(r.lo, p.isChecked(r.check)); p.setEnabled(r.hi, p.isChecked(r.check)) }
            p.on(r.check, update)
            update()
        }
        p.setChecked(782, AppSettings.shared.trimmingSort)
        guard dlg.run(over: window) == IDC.ok else { return nil }
        let sort = p.isChecked(782)
        return rows.enumerated().map { k, r in
            var lo = p.number(r.lo, or: k < ranges.count ? ranges[k].1 : 0)
            var hi = p.number(r.hi, or: k < ranges.count ? ranges[k].2 : 1)
            if sort && lo > hi { swap(&lo, &hi) }
            return (p.isChecked(r.check), lo, hi)
        }
    }

    // MARK: - 用紙設定(印刷サイズの設定)

    static func printSize(page: PageSetup, over window: NSWindow?) -> PageSetup? {
        let dlg = Dialog(.printSize)
        let p = dlg.page
        p.setItems(787, Lists.paperSizes.map(\.0))
        let w = min(page.paperWidth, page.paperHeight), h = max(page.paperWidth, page.paperHeight)
        let k = Lists.paperSizes.firstIndex { $0.1 == w && $0.2 == h } ?? (Lists.paperSizes.count - 1)
        p.select(787, k)
        p.setInteger(788, page.paperWidth)
        p.setInteger(789, page.paperHeight)
        p.setChecked(790, !page.landscape)
        p.setChecked(791, page.landscape)
        p.setItems(810, Lists.printScales)
        p.setText(810, String(page.tail.first ?? 100))
        p.on(787) {
            let i = p.selectedIndex(787)
            guard i >= 0, i < Lists.paperSizes.count, Lists.paperSizes[i].1 > 0 else { return }
            p.setInteger(788, Lists.paperSizes[i].1)
            p.setInteger(789, Lists.paperSizes[i].2)
        }
        guard dlg.run(over: window) == IDC.ok else { return nil }
        var n = page
        n.paperWidth = max(p.integer(788, or: page.paperWidth), 10)
        n.paperHeight = max(p.integer(789, or: page.paperHeight), 10)
        n.landscape = p.isChecked(791)
        var tail = page.tail
        if tail.isEmpty { tail = [100, 1] }
        tail[0] = max(min(p.integer(810, or: tail[0]), 400), 10)
        if tail.count > 1 { tail[1] = max(p.selectedIndex(787), 0) }
        n.tail = tail
        return n
    }

    // MARK: - コピー領域の設定(図面コピー)

    struct ClipRegion { var margins: [Double]; var scale: Double; var dpi: Double }

    /// bounds: 描いてあるものの範囲(mm)。戻り値は余白・縮小率・解像度
    static func clipRegion(bounds: CGRect, over window: NSWindow?) -> ClipRegion? {
        let dlg = Dialog(.copyRegion)
        let p = dlg.page
        let s = AppSettings.shared
        let ids = [(787, 778), (788, 779), (789, 780), (790, 781)]
        let edges = [bounds.minX, bounds.minY, bounds.maxX, bounds.maxY]
        func fill(_ m: [Double]) {
            for (k, (marginID, posID)) in ids.enumerated() {
                p.setNumber(marginID, m[k])
                let sign: Double = k < 2 ? -1 : 1
                p.setText(posID, Num.f2(Double(edges[k]) + sign * m[k]))
            }
        }
        fill(s.copyMargins)
        p.setNumber(791, s.copyScale)
        p.setNumber(792, s.exportDPI)
        p.setChecked(794, true)
        p.setEnabled(794, false)
        p.setEnabled(792, true)
        for (k, (marginID, posID)) in ids.enumerated() {
            p.on(marginID) {
                let sign: Double = k < 2 ? -1 : 1
                p.setText(posID, Num.f2(Double(edges[k]) + sign * p.number(marginID, or: 0)))
            }
        }
        dlg.buttons[920] = {
            fill([10, 10, 10, 10])
            p.setNumber(791, 100)
            return false
        }
        guard dlg.run(over: window) == IDC.ok else { return nil }
        let m = ids.map { p.number($0.0, or: 10) }
        let r = ClipRegion(margins: m, scale: max(p.number(791, or: 100), 1), dpi: max(p.number(792, or: 300), 36))
        s.copyMargins = r.margins
        s.copyScale = r.scale
        s.exportDPI = r.dpi
        return r
    }
}
