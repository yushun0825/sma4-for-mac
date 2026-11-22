import AppKit
import Sma4Core

/// 確認用: 画面に出さずに、データを開く → マウスで動かす → 取り消す → 保存して開き直す、を通して確かめる。
/// SMA4_TEST_INPUT=データファイル SMA4_TEST_OUTPUT=出力フォルダ "Sma4 for Mac" --selftest
@MainActor
enum SelfTestRunner {
    static var isActive: Bool { CommandLine.arguments.contains("--selftest") }

    static var failures = 0

    static func check(_ ok: Bool, _ name: String, _ detail: @autoclosure () -> String = "") {
        if ok { print("PASS \(name)") } else { failures += 1; print("FAIL \(name) \(detail())") }
    }

    static func run() {
        let env = ProcessInfo.processInfo.environment
        guard let inPath = env["SMA4_TEST_INPUT"], let outPath = env["SMA4_TEST_OUTPUT"] else { NSApp.terminate(nil); return }
        NSApp.setActivationPolicy(.accessory)
        setvbuf(stdout, nil, _IOLBF, 0)
        let input = URL(fileURLWithPath: inPath)
        let outDir = URL(fileURLWithPath: outPath, isDirectory: true)
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        DispatchQueue.main.async {
            do { try scenario(input: input, outDir: outDir) } catch {
                failures += 1
                print("FAIL exception \(error)")
            }
            print(failures == 0 ? "ALL PASSED" : "\(failures) FAILED")
            NSApp.terminate(nil)
        }
    }

    static func mouse(_ type: NSEvent.EventType, _ p: CGPoint, in window: NSWindow, clicks: Int = 1) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clicks, pressure: 1)!
    }

    /// 取り消しはイベントごとにまとまるので、操作ごとに RunLoop を 1 回まわす
    static func tick() {
        RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.02))
    }

    /// 1 回の操作 = 1 つの取り消しの単位(実際のアプリではイベントごとに自動で区切られる)
    static var undo: UndoManager?
    static func step(_ body: () -> Void) {
        undo?.beginUndoGrouping()
        body()
        undo?.endUndoGrouping()
    }

    static func drag(_ canvas: CanvasView, from page: CGPoint, by delta: CGSize) {
        tick()
        guard let window = canvas.window else { return }
        let v = canvas.viewPoint(page)
        let w0 = canvas.convert(v, to: nil)
        // ビューは上下が逆(flipped)なので、ウインドウの座標では y を引く
        let w1 = canvas.convert(CGPoint(x: v.x + delta.width, y: v.y + delta.height), to: nil)
        canvas.mouseDown(with: mouse(.leftMouseDown, w0, in: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, CGPoint(x: (w0.x + w1.x) / 2, y: (w0.y + w1.y) / 2), in: window))
        canvas.mouseDragged(with: mouse(.leftMouseDragged, w1, in: window))
        canvas.mouseUp(with: mouse(.leftMouseUp, w1, in: window))
        tick()
    }

    static func scenario(input: URL, outDir: URL) throws {
        // 1. データファイルを開く
        let dc = NSDocumentController.shared
        let type = try dc.typeForContents(of: input)
        check(type == Sma4Document.dataType, "データファイルの種類", type)
        guard let doc = try dc.makeDocument(withContentsOf: input, ofType: type) as? Sma4Document else { throw CocoaError(.fileReadUnknown) }
        check(doc.fileURL == nil, "データファイルは名前のないグラフとして開く")
        check(doc.fileType == Sma4Document.smpType, "保存の形式は SMP", doc.fileType ?? "nil")
        check(doc.project.graphs.count == 1 && doc.project.graphs[0].series.count == 1, "グラフ 1 枚・系列 1 つ")
        let pts = doc.plotData()[0][0].finitePoints
        check(pts.count == 7, "見出しとコメント行を除いた 7 点", "\(pts.count)")
        let ax = doc.project.graphs[0].axes[0]
        check(ax.from <= 10 && ax.to >= 1000, "X の範囲が自動で合う", "\(ax.from)〜\(ax.to)")
        doc.undoManager?.groupsByEvent = false
        undo = doc.undoManager

        doc.makeWindowControllers()
        guard let wc = doc.windowControllers.first as? GraphWindowController, let window = wc.window else { throw CocoaError(.fileReadUnknown) }
        window.setFrame(NSRect(x: -8000, y: -8000, width: 1100, height: 860), display: true)
        window.contentView?.layoutSubtreeIfNeeded()
        let canvas = wc.canvas
        canvas.updateSize()

        // 2. 軸を対数にして、X 軸タイトルを入れる
        step {
            doc.update(graph: 0, "X-Axis") { g in
                g.axes[0].scaleType = .logNormal
                g.axes[0].from = 10; g.axes[0].to = 1000; g.axes[0].increment = 10; g.axes[0].division = 10
            }
        }
        var t = TextObject()
        t.kind = .xTitle
        t.x = 5000; t.y = 11800
        t.text = "Frequency [Hz]"
        let item = ObjectItem(.text(t))
        step { doc.update(graph: 0, "X軸タイトル") { $0.objects.append(item) } }
        check(doc.project.graphs[0].objects.count == 1, "文字を入れる")

        // 3. 文字をドラッグで動かす(右へ 40 pt、下へ 20 pt)
        let renderer = doc.renderer()
        guard let b = renderer.objectBounds(item.object, graphIndex: 0) else { throw CocoaError(.fileReadUnknown) }
        let g0 = doc.project.graphs[0]
        let center = CGPoint(x: b.midX, y: b.midY).applying(GraphRenderer.graphTransform(g0))
        step { drag(canvas, from: center, by: CGSize(width: 40, height: 20)) }
        guard case .text(let moved) = doc.project.graphs[0].objects[0].object else { throw CocoaError(.fileReadUnknown) }
        let expectDX = 40 / canvas.unit, expectDY = 20 / canvas.unit
        check(abs(CGFloat(moved.x - t.x) - expectDX) <= 60 && abs(CGFloat(moved.y - t.y) - expectDY) <= 60,
              "文字をドラッグで動かす", "dx \(moved.x - t.x) 期待 \(Int(expectDX)) / dy \(moved.y - t.y) 期待 \(Int(expectDY))")
        check(moved.x % 100 == 0 && moved.y % 100 == 0, "1 mm にスナップする(既定)", "\(moved.x), \(moved.y)")

        // 4. 取り消す
        doc.undoManager?.undo()
        if let first = doc.project.graphs[0].objects.first, case .text(let back) = first.object {
            check(back.x == t.x && back.y == t.y, "取り消すと元の位置に戻る", "\(back.x), \(back.y)")
        } else {
            check(false, "取り消すと元の位置に戻る", "文字まで消えた")
        }
        doc.undoManager?.redo()
        tick()
        if let first = doc.project.graphs[0].objects.first, case .text(let again) = first.object {
            check(again.x == moved.x, "やり直すと動かした位置に戻る")
        }

        // 5. 枠の右下の角をドラッグして大きくする
        let w0 = doc.project.graphs[0].width, h0 = doc.project.graphs[0].height
        let corner = CGPoint(x: g0.left + g0.width, y: g0.top + g0.height)
        step { drag(canvas, from: corner, by: CGSize(width: 30, height: 15)) }
        let w1 = doc.project.graphs[0].width, h1 = doc.project.graphs[0].height
        check(w1 > w0 && h1 > h0, "角のドラッグでグラフが大きくなる", "\(w0)→\(w1), \(h0)→\(h1)")

        // 6. U 軸(上の辺)をドラッグしてグラフ全体を動かす
        let g1 = doc.project.graphs[0]
        let topEdge = CGPoint(x: g1.left + g1.width / 2, y: g1.top)
        step { drag(canvas, from: topEdge, by: CGSize(width: 0, height: 30)) }
        check(doc.project.graphs[0].top > g1.top && doc.project.graphs[0].width == g1.width, "上の辺のドラッグでグラフが動く",
              "\(g1.top)→\(doc.project.graphs[0].top)")

        // 7. 最小二乗(2 次)
        step {
            doc.update(graph: 0, "最小二乗") { g in
                g.series[0].kind = .polynomialLSQ; g.series[0].kindRaw = 1; g.series[0].lsqOrder = 2
                g.series[0].curveStart = 10; g.series[0].curveEnd = 1000; g.series[0].curveSpacing = .exponential
            }
        }
        let d = doc.plotData()[0][0]
        check(d.fit != nil && d.curve.count > 50, "最小二乗の曲線ができる", d.error ?? "")

        // 8. 凡例
        var legend = TextObject()
        legend.text = GraphOps.legendText(seriesIndices: [0])
        legend.x = 9000; legend.y = 1500
        step { doc.update(graph: 0, "凡例") { $0.objects.append(ObjectItem(.text(legend))) } }
        check(doc.undoManager?.undoActionName == "凡例", "取り消しのメニューに操作の名前が出る", doc.undoManager?.undoActionName ?? "")

        // 9. 保存して読み直す
        let url = outDir.appendingPathComponent("selftest.SMP")
        try doc.write(to: url, ofType: Sma4Document.smpType)
        let raw = try Data(contentsOf: url)
        let head = String(data: raw.prefix(40), encoding: .ascii) ?? ""
        check(head.hasPrefix(" Sma4Win ver. 1.8  SMP file\r\n"), "Sma4 1.8 の見出しと CRLF", head)
        let sjisHeader = "周波数[Hz],加速度[G]".data(using: Sma4TextEncoding.windows31J)!
        check(raw.range(of: sjisHeader) != nil, "データは Shift_JIS で埋め込む")
        let back = try SMPReader.read(data: raw, fileName: url.lastPathComponent)
        check(back.graphs.count == 1 && back.graphs[0].series[0].kind == .polynomialLSQ && back.graphs[0].series[0].lsqOrder == 2,
              "保存した SMP に最小二乗の設定が残る")
        check(back.graphs[0].axes[0].scaleType == .logNormal, "保存した SMP に対数軸が残る")
        check(back.graphs[0].objects.count == 2, "保存した SMP に文字と凡例が残る", "\(back.graphs[0].objects.count)")
        check(back.dataFile(named: input.lastPathComponent)?.lines.count == doc.project.dataFile(named: input.lastPathComponent)?.lines.count,
              "データの行数が同じ")

        // 10. 開き直して同じ絵になるか(系列の値で比べる)
        guard let doc2 = try dc.makeDocument(withContentsOf: url, ofType: Sma4Document.smpType) as? Sma4Document else { throw CocoaError(.fileReadUnknown) }
        check(doc2.plotData()[0][0].finitePoints.count == pts.count, "開き直しても 7 点")
        let r1 = GraphExporter.pngData(renderer: doc.renderer(), dpi: 72)
        let r2 = GraphExporter.pngData(renderer: doc2.renderer(), dpi: 72)
        check(r1 != nil && r1 == r2, "開き直しても同じ絵になる")

        // 11. 図面の書き出し(PDF)
        let pdf = GraphExporter.pdfData(renderer: doc.renderer())
        check(pdf.count > 1000 && pdf.starts(with: Array("%PDF".utf8)), "PDF に書き出せる", "\(pdf.count) bytes")
        try pdf.write(to: outDir.appendingPathComponent("selftest.pdf"))

        window.orderFrontRegardless()
        DialogCapture.save(window, to: outDir.appendingPathComponent("selftest_window.png"))
        window.orderOut(nil)

        // 12. 起動したときの「新規」
        guard let blank = try dc.makeUntitledDocument(ofType: Sma4Document.smpType) as? Sma4Document else { throw CocoaError(.fileReadUnknown) }
        check(blank.project.graphs.count == 1 && blank.project.graphs[0].series.isEmpty, "新規は空のグラフ 1 枚")
        blank.makeWindowControllers()
        check(blank.windowControllers.first?.window != nil, "新規のウインドウができる")

        // 13. メニューの全項目が、どれかの受け手につながっている
        var unhandled: [String] = []
        let receivers: [AnyObject] = [wc, window, canvas, doc, NSApp, NSApp.delegate as AnyObject, dc]
        func walk(_ menu: NSMenu) {
            for item in menu.items {
                if let sub = item.submenu { walk(sub); continue }
                guard let action = item.action else { continue }
                if item.target != nil { continue }
                if !receivers.contains(where: { $0.responds(to: action) }) { unhandled.append("\(item.title)(\(action))") }
            }
        }
        if let main = NSApp.mainMenu { walk(main) }
        check(unhandled.isEmpty, "メニューの全項目がつながっている", unhandled.joined(separator: ", "))
        // メニューの有効・無効の判定で落ちない
        if let main = NSApp.mainMenu {
            var count = 0
            func validate(_ menu: NSMenu) {
                for item in menu.items {
                    if let sub = item.submenu { validate(sub); continue }
                    if item.action != nil, wc.responds(to: item.action!) { _ = wc.validateMenuItem(item); count += 1 }
                }
            }
            validate(main)
            check(count > 40, "メニューの有効・無効を判定できる", "\(count)")
        }

        // 14. ツールバーのボタン(14 個)がつながっていて、絵が付いている
        let toolbarButtons = wc.toolbarStrip.buttons
        check(toolbarButtons.count == 14, "ツールバーのボタンが 14 個", "\(toolbarButtons.count)")
        check(toolbarButtons.allSatisfy { b, spec in receivers.contains(where: { $0.responds(to: spec.action) }) }, "ツールバーのボタンがつながっている")
        check(toolbarButtons.allSatisfy { $0.0.image != nil }, "ツールバーに絵が付いている")

        // 15. Data Mask: 範囲の中の点が消える
        let before = doc.plotData()[0][0].finitePoints.count
        step { doc.update(graph: 0, "Data Mask") { $0.masks = [DataMask(target: 1, xMin: 0, xMax: 150, yMin: -1e9, yMax: 1e9)] } }
        let after = doc.plotData()[0][0].finitePoints.count
        check(after < before, "Data Mask の範囲の点を除く", "\(before)→\(after)")
        step { doc.update(graph: 0, "Data Mask の削除") { $0.masks = [] } }

        // 16. 全部のダイアログを組み立てられる(落ちない)
        DialogCapture.outDir = outDir.appendingPathComponent("dialogs")
        try? FileManager.default.createDirectory(at: DialogCapture.outDir!, withIntermediateDirectories: true)
        SnapshotRunner.dialogs(doc: doc, wc: wc, window: window, outDir: DialogCapture.outDir!)
        DialogCapture.outDir = nil
        let made = (try? FileManager.default.contentsOfDirectory(atPath: outDir.appendingPathComponent("dialogs").path))?.count ?? 0
        check(made >= 30, "ダイアログを画像にできる", "\(made) 枚")
    }
}
