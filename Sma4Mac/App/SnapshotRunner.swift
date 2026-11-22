import AppKit
import Sma4Core

/// 確認用: 画面に出さずに、主窓と全部のダイアログを PNG にして終わる。
/// SMA4_TEST_INPUT=入力.smp SMA4_TEST_OUTPUT=出力フォルダ "Sma4 for Mac" --snapshot
/// (ファイルの場所を引数にすると AppKit が書類として開こうとするので、環境変数で渡す)
@MainActor
enum SnapshotRunner {
    static var isActive: Bool { CommandLine.arguments.contains("--snapshot") }

    static func run() {
        let env = ProcessInfo.processInfo.environment
        guard let inPath = env["SMA4_TEST_INPUT"], let outPath = env["SMA4_TEST_OUTPUT"] else { NSApp.terminate(nil); return }
        NSApp.setActivationPolicy(.accessory)
        let input = URL(fileURLWithPath: inPath)
        let outDir = URL(fileURLWithPath: outPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        DispatchQueue.main.async {
            do {
                let dc = NSDocumentController.shared
                let type = try dc.typeForContents(of: input)
                guard let doc = try dc.makeDocument(withContentsOf: input, ofType: type) as? Sma4Document else { throw CocoaError(.fileReadUnknown) }
                doc.makeWindowControllers()
                guard let wc = doc.windowControllers.first as? GraphWindowController, let window = wc.window else { throw CocoaError(.fileReadUnknown) }
                window.setFrame(NSRect(x: -9000, y: -9000, width: 820, height: 660), display: true)
                window.orderFrontRegardless()
                window.contentView?.layoutSubtreeIfNeeded()
                wc.canvas.updateSize()
                wc.mouseMovedOnCanvas(page: CGPoint(x: 9000, y: 8000))
                DialogCapture.save(window, to: outDir.appendingPathComponent("window.png"))
                wc.togglePreview(nil)
                DialogCapture.save(window, to: outDir.appendingPathComponent("window_preview.png"))
                wc.togglePreview(nil)
                if let g = doc.activeGraph, let id = g.objects.first?.id {
                    wc.canvas.selection = [id]
                    DialogCapture.save(window, to: outDir.appendingPathComponent("window_selected.png"))
                    wc.canvas.selection = []
                }
                dialogs(doc: doc, wc: wc, window: window, outDir: outDir)
                window.orderOut(nil)
                print("snapshot ok: \(outDir.path)")
            } catch {
                print("snapshot error: \(error)")
            }
            NSApp.terminate(nil)
        }
    }

    static func dialogs(doc: Sma4Document, wc: GraphWindowController, window: NSWindow, outDir: URL) {
        guard let g = doc.activeGraph else { return }
        DialogCapture.outDir = outDir
        defer { DialogCapture.outDir = nil }
        func cap(_ name: String, _ body: () -> Void) {
            DialogCapture.name = name
            body()
        }
        cap("axis_x") { _ = GraphDialogs.axis(0, graph: g, over: window) }
        cap("graph_property") { _ = GraphDialogs.graphProperty(graph: g, over: window, startPage: 0) }
        cap("trimming") { _ = GraphDialogs.trimming(ranges: [(true, 0, 10), (true, 0, 5), (false, 0, 10), (false, 0, 5)], over: window) }
        cap("print_size") { _ = GraphDialogs.printSize(page: g.page, over: window) }
        cap("clip_region") { _ = GraphDialogs.clipRegion(bounds: CGRect(x: 20, y: 10, width: 160, height: 120), over: window) }
        if let si = g.series.firstIndex(where: { $0.kind.hasCurve }) ?? g.series.indices.first {
            let s = g.series[si]
            cap("data_property") {
                _ = DataDialogs.property(series: s, index: si, graph: g, project: doc.project, others: g.series, over: window)
            }
            var poly = s; poly.kind = .polynomialLSQ; poly.kindRaw = 1; poly.lsqOrder = 3
            cap("lsq_polynomial") { _ = AnalysisDialogs.leastSquares(series: poly, over: window) }
            var gen = s; gen.kind = .generalLSQ; gen.kindRaw = 7; gen.generalFunction = "a*exp(b*x)"
            cap("lsq_general") { _ = AnalysisDialogs.leastSquares(series: gen, over: window) }
            var spl = s; spl.kind = .spline; spl.kindRaw = 2
            cap("spline") { _ = AnalysisDialogs.leastSquares(series: spl, over: window) }
        }
        let names = g.series.map { DataDialogs.managerTitle($0) }
        cap("data_manager") { _ = DataDialogs.manager(series: g.series, over: window) }
        cap("list_one") { _ = ListDialogs.chooseOne(title: "最小二乗するファイルの選択", items: names + ["NEW.DAT"], over: window) }
        cap("list_many") { _ = ListDialogs.chooseMany(title: "表示するファイルの選択", items: names, selected: IndexSet(names.indices), over: window) }
        cap("input") { _ = ListDialogs.input(title: "描画関数の入力", prompt: "式:", text: "sin(x)", over: window) }
        cap("mask") {
            _ = DataDialogs.maskChoice(masks: [DataMask(target: 0, xMin: 2.5, xMax: 5.5, yMin: 0, yMax: 100),
                                               DataMask(target: 1, xMin: 1, xMax: 2, yMin: 0.5, yMax: 3)], over: window)
        }
        cap("mask_target") { _ = ListDialogs.chooseMaskTarget(items: names, over: window) }
        // 文字が無いグラフでも、見本の文字で画像にする
        var sampleText = TextObject()
        sampleText.text = "見本の文字 ^2@"
        let t = g.objects.compactMap({ item -> TextObject? in if case .text(let t) = item.object { return t } else { return nil } }).first ?? sampleText
        cap("text") { _ = ObjectDialogs.text(t, title: t.kind.title, isNew: false, over: window) }
        var arrow = ShapeObject(); arrow.x1 = 10; arrow.y1 = 10; arrow.x2 = 30; arrow.y2 = 20; arrow.headMode = 1; arrow.headOpen = 30
        cap("arrow") { _ = ObjectDialogs.arrow(arrow, isNew: false, over: window) }
        var box = ShapeObject(); box.objectType = 3; box.shapeType = 3; box.x1 = 10; box.y1 = 10; box.x2 = 60; box.y2 = 30
        cap("box") { _ = ObjectDialogs.box(box, isNew: false, over: window) }
        var dot = DotObject(); dot.dotType = 2; dot.x = 3000; dot.y = 2000
        cap("dot") { _ = ObjectDialogs.dot(dot, isNew: false, over: window) }
        cap("picture") { _ = ObjectDialogs.picture(PictureObject(path: ""), isNew: true, imageSize: { _ in nil }, over: window) }
        cap("constants") { _ = AnalysisDialogs.constants(g.constants, over: window, apply: { _ in }) }
        cap("information") { _ = AnalysisDialogs.information(title: "DATA1.DAT (F多項式)", lines: ["a0=1.00000000e+00", "a1=2.50000000e-01", "|r|=9.98765432e-01"], over: window) }
        cap("fitting_cond") { _ = AnalysisDialogs.fittingCondition(PeakFitSettings(), over: window) }
        cap("settings") { MiscDialogs.settings(over: window) }
        cap("about") { MiscDialogs.about(over: window) }
        cap("calculator") { Calculator.run(over: window, constants: []) }
        // 値を読む(作業面と一緒に出したままにする窓)
        if !g.series.isEmpty {
            wc.readValueSeries = 0
            wc.canvas.mode = .readValue
            wc.canvas.setReadValue(series: 0, index: 2)
            let p = ReadValuePanel(controller: wc)
            p.refresh()
            p.panel.setFrameOrigin(NSPoint(x: -9000, y: -9000))
            p.panel.orderFrontRegardless()
            DialogCapture.save(p.panel, to: outDir.appendingPathComponent("read_value.png"))
            p.panel.orderOut(nil)
            DialogCapture.save(window, to: outDir.appendingPathComponent("window_readvalue.png"))
            wc.canvas.mode = .normal
        }
    }
}
