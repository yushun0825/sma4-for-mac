import AppKit
import Sma4Core

/// ツールメニュー・ヘルプメニューのダイアログ(設定・計算機・このアプリについて)と、値を読む
@MainActor
enum MiscDialogs {
    static let snapItems: [(String, Double)] = [("しない", 0), ("0.5mm", 0.5), ("1mm", 1), ("2mm", 2), ("5mm", 5)]
    static let gridItems: [(String, Double)] = [("表示しない", 0), ("5mm", 5), ("10mm", 10)]
    static let screenSizes = ["50", "70", "100", "150", "200"]

    // MARK: - 設定(file・etc.)

    static func settings(over window: NSWindow?) {
        let s = AppSettings.shared
        let sheet = PropertySheet(title: "設定", pages: [("ファイル", .settingsFiles), ("表示", .settingsView)])
        let p1 = sheet.page(0), p2 = sheet.page(1)
        p1.setChecked(787, s.saveDataWithGraph)
        p1.setChecked(794, s.omitPathInSameFolder)
        p1.setChecked(900, s.preferEmbeddedData)
        p1.setChecked(899, s.textSMP)
        p1.setText(902, s.wildcard)
        p1.setText(781, s.editorPath)
        p1.setChecked(795, s.propertiesOnLaunchOpen)
        p1.setChecked(821, s.autoDotType)
        p1.setChecked(822, s.autoLineType)
        p1.setChecked(823, s.autoDotColor)
        p1.setChecked(824, s.autoLineColor)
        p1.setChecked(828, s.autoScaleX)
        p1.setChecked(829, s.autoScaleY)
        p1.on(782) {
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.application]
            panel.directoryURL = URL(fileURLWithPath: "/Applications")
            panel.message = "データファイルの編集に使うエディタを選んでください。"
            if panel.runModal() == .OK, let url = panel.url { p1.setText(781, url.path) }
        }

        p2.setChecked(790, s.clipToFrame)
        p2.setChecked(788, s.showToolbar)
        p2.setChecked(789, s.showStatusBar)
        p2.setChecked(903, s.printBackground)
        p2.setChecked(825, s.readValueSort)
        p2.setChecked(914, s.trimmingSort)
        p2.setItems(791, snapItems.map(\.0))
        p2.select(791, snapItems.firstIndex { $0.1 == s.snapMM } ?? 2)
        p2.setItems(792, gridItems.map(\.0))
        p2.select(792, gridItems.firstIndex { $0.1 == s.gridMM } ?? 0)
        p2.setColor(710, s.gridColor)
        p2.setColor(708, s.backgroundColor)
        p2.setColor(709, s.readValueColor)
        p2.setItems(793, screenSizes)
        p2.setText(793, Num.g(s.screenSize))
        p2.setNumber(778, s.superscriptScale)
        p2.setNumber(779, s.superscriptRise)
        p2.setNumber(780, s.subscriptDrop)
        p2.setChecked(916, s.printFooter)

        guard sheet.run(over: window) == IDC.ok else { return }
        s.saveDataWithGraph = p1.isChecked(787)
        s.omitPathInSameFolder = p1.isChecked(794)
        s.preferEmbeddedData = p1.isChecked(900)
        s.textSMP = p1.isChecked(899)
        s.wildcard = p1.text(902).isEmpty ? "*.*" : p1.text(902)
        s.editorPath = p1.text(781)
        s.propertiesOnLaunchOpen = p1.isChecked(795)
        s.autoDotType = p1.isChecked(821)
        s.autoLineType = p1.isChecked(822)
        s.autoDotColor = p1.isChecked(823)
        s.autoLineColor = p1.isChecked(824)
        s.autoScaleX = p1.isChecked(828)
        s.autoScaleY = p1.isChecked(829)
        s.clipToFrame = p2.isChecked(790)
        s.showToolbar = p2.isChecked(788)
        s.showStatusBar = p2.isChecked(789)
        s.printBackground = p2.isChecked(903)
        s.readValueSort = p2.isChecked(825)
        s.trimmingSort = p2.isChecked(914)
        s.snapMM = snapItems[max(0, min(p2.selectedIndex(791), snapItems.count - 1))].1
        s.gridMM = gridItems[max(0, min(p2.selectedIndex(792), gridItems.count - 1))].1
        s.gridColor = p2.color(710)
        s.backgroundColor = p2.color(708)
        s.readValueColor = p2.color(709)
        s.screenSize = max(min(p2.number(793, or: 70), 400), 10)
        s.superscriptScale = p2.number(778, or: 70)
        s.superscriptRise = p2.number(779, or: 50)
        s.subscriptDrop = p2.number(780, or: 20)
        s.printFooter = p2.isChecked(916)
    }

    // MARK: - Sma4 for Mac について

    static func about(over window: NSWindow?) {
        let dlg = Dialog(.about, title: "Sma4 for Mac について")
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        dlg.page.setLabel(103, "バージョン \(version)")
        dlg.run(over: window)
    }
}

/// 四則計算機(数式変換の機能で計算する)。1 行の入力の窓で「式=答」を出す
@MainActor
enum Calculator {
    static func run(over window: NSWindow?, constants: [Double]) {
        let dlg = Dialog(.input, title: "四則計算機")
        let p = dlg.page
        p.setLabel(901, "式:")
        p.setText(902, "")
        dlg.validate = {
            let e = p.text(902).trimmingCharacters(in: .whitespaces)
            guard !e.isEmpty else { return true }
            do {
                let v = try Expression(e).evaluateScalar(constants: ExprContext.constantsDictionary(constants))
                p.setLabel(901, String(format: "%@=%.10g", e, v))
                p.field(902)?.selectText(nil)
            } catch {
                p.setLabel(901, "Over(Under)flow Error / " + ((error as? ExpressionError)?.message ?? "計算できません"))
            }
            return false
        }
        dlg.page.setText(IDC.cancel, "閉じる")
        dlg.page.setText(IDC.ok, "=")
        dlg.run(over: window)
    }
}

/// 値を読む。窓を出したまま作業面の点を動かせる
@MainActor
final class ReadValuePanel: NSObject, NSWindowDelegate {
    weak var controller: GraphWindowController?
    let panel: NSPanel
    let page = TemplateView(.readValue)
    private var order: [Int] = []

    init(controller: GraphWindowController) {
        self.controller = controller
        panel = NSPanel(contentRect: NSRect(origin: .zero, size: page.frame.size),
                        styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: true)
        super.init()
        panel.title = "値を読む"
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.hidesOnDeactivate = true
        let content = FlippedView(frame: NSRect(origin: .zero, size: page.frame.size))
        content.addSubview(page)
        panel.contentView = content
        panel.delegate = self
        page.onPush = { [weak self] id in self?.pushed(id) }
        page.on(820) { [weak self] in self?.slid() }
    }

    func show() {
        guard let w = controller?.window else { return }
        let f = w.frame
        panel.setFrameTopLeftPoint(NSPoint(x: f.maxX - panel.frame.width - 16, y: f.maxY - 90))
        w.addChildWindow(panel, ordered: .above)
        panel.orderFront(nil)
        refresh()
    }

    func close() {
        panel.parent?.removeChildWindow(panel)
        panel.orderOut(nil)
    }

    func windowWillClose(_ notification: Notification) {
        if controller?.canvas.mode == .readValue { controller?.canvas.mode = .normal }
    }

    /// 点の順番(設定の「ReadValueはsortする」なら X の小さい順)
    func points() -> SeriesPlotData? {
        guard let c = controller, let doc = c.doc, let rv = c.canvas.readValue else { return nil }
        let data = doc.plotData()
        guard rv.graph < data.count, rv.series < data[rv.graph].count else { return nil }
        let d = data[rv.graph][rv.series]
        let valid = (0..<min(d.x.count, d.y.count)).filter { d.x[$0].isFinite && d.y[$0].isFinite }
        order = AppSettings.shared.readValueSort ? valid.sorted { d.x[$0] < d.x[$1] } : valid
        return d
    }

    func refresh() {
        guard let c = controller, let rv = c.canvas.readValue, let d = points() else { return }
        let pos = order.firstIndex(of: rv.index) ?? 0
        page.setLabel(789, "\(rv.index + 1) / \(min(d.x.count, d.y.count))")
        page.setText(787, String(format: "%6.4e", rv.x))
        page.setText(788, String(format: "%6.4e", rv.y))
        if let doc = c.doc, rv.graph < doc.project.graphs.count, rv.series < doc.project.graphs[rv.graph].series.count {
            let g = doc.project.graphs[rv.graph]
            let s = g.series[rv.series]
            page.setLabel(904, g.horizontalAxisIndex(for: s) == 2 ? "U：" : "X：")
            page.setLabel(905, g.verticalAxisIndex(for: s) == 3 ? "R：" : "Y：")
        }
        if let sl = page.slider(820) {
            sl.minValue = 0
            sl.maxValue = Double(max(order.count - 1, 1))
            sl.doubleValue = Double(pos)
        }
        if let mark = c.canvas.readMark, mark.series == rv.series {
            let a = min(order.firstIndex(of: mark.index) ?? pos, pos), b = max(order.firstIndex(of: mark.index) ?? pos, pos)
            let idx = order[a...b]
            let ax = idx.map { d.x[$0] }.reduce(0, +) / Double(idx.count)
            let ay = idx.map { d.y[$0] }.reduce(0, +) / Double(idx.count)
            page.setLabel(906, String(format: "%6.4e", ax))
            page.setLabel(907, String(format: "%6.4e", ay))
        }
    }

    func move(to pos: Int) {
        guard let c = controller, let rv = c.canvas.readValue, !order.isEmpty else { return }
        let p = max(0, min(order.count - 1, pos))
        c.canvas.setReadValue(series: rv.series, index: order[p])
        c.readValueChanged()
    }

    private func pushed(_ id: Int) {
        guard let c = controller, let rv = c.canvas.readValue, points() != nil else {
            if id == IDC.ok { controller?.canvas.mode = .normal }
            return
        }
        let pos = order.firstIndex(of: rv.index) ?? 0
        switch id {
        case 784: move(to: 0)
        case 778: move(to: pos - 10)
        case 779: move(to: pos - 1)
        case 780: move(to: pos + 1)
        case 781: move(to: pos + 10)
        case 785: move(to: order.count - 1)
        case 782:  // Mark
            c.canvas.readMark = rv
            page.setLabel(906, ""); page.setLabel(907, "")
        case 783:  // Average: Mark との間の平均
            if c.canvas.readMark == nil { c.canvas.readMark = rv }
            refresh()
        case IDC.ok:
            c.canvas.mode = .normal
        default: break
        }
    }

    private func slid() {
        guard let sl = page.slider(820) else { return }
        _ = points()
        move(to: Int(sl.doubleValue.rounded()))
    }
}
