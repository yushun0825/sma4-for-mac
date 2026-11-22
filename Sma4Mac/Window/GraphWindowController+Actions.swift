import AppKit
import UniformTypeIdentifiers
import Sma4Core

/// メニュー・ツールバー・右ボタンのメニューから呼ぶ操作(メニューの並びの順)
extension GraphWindowController {
    static let objectPasteboardType = NSPasteboard.PasteboardType("io.github.yushun0825.sma4mac.object")
    static let maxGraphs = 50
    static let maxSeries = 40

    var gi: Int { doc?.activeGraphIndex ?? 0 }

    /// 系列を 1 つ選ばせる(1 つしかなければそのまま)
    func chooseSeries(_ title: String, where filter: (Series) -> Bool = { _ in true }) -> Int? {
        guard let g = doc?.activeGraph else { return nil }
        let indices = g.series.indices.filter { filter(g.series[$0]) }
        guard !indices.isEmpty else { return nil }
        if indices.count == 1 { return indices[0] }
        guard let k = ListDialogs.chooseOne(title: title, items: indices.map { DataDialogs.managerTitle(g.series[$0]) }, over: window),
              k >= 0, k < indices.count else { return nil }
        return indices[k]
    }

    // MARK: - ファイル

    @objc func addGraph(_ sender: Any?) {
        guard let doc else { return }
        guard doc.project.graphs.count < GraphWindowController.maxGraphs else {
            MessageBox.show("\(GraphWindowController.maxGraphs)個以上のグラフは描けません", title: "エラー"); return
        }
        var g = AppSettings.shared.defaultGraph()
        g.name = "Untitled\(doc.project.graphs.count + 1).SMP"
        if let last = doc.project.graphs.last {
            g.left = last.left + 1000
            g.top = last.top + 1000
            g.page = last.page
        }
        doc.update("新規グラフの追加") { $0.graphs.append(g) }
        doc.activeGraphIndex = doc.project.graphs.count - 1
        canvas.selection = []
    }

    @objc func deleteGraph(_ sender: Any?) {
        guard let doc, let g = doc.activeGraph else { return }
        if !g.series.isEmpty || !g.objects.isEmpty {
            guard MessageBox.confirm("保存せずに削除しますか？", title: "Sma4 for Mac") else { return }
        }
        let i = gi
        doc.update("グラフの削除") { p in
            p.graphs.remove(at: i)
            if p.graphs.isEmpty {
                var g = AppSettings.shared.defaultGraph(); g.name = "Untitled.SMP"; p.graphs = [g]
            }
            GraphOps.pruneData(&p)
        }
        doc.activeGraphIndex = min(i, doc.project.graphs.count - 1)
        doc.soloGraph = nil
    }

    @objc func deleteAllGraphs(_ sender: Any?) {
        guard let doc else { return }
        guard MessageBox.confirm("作業中の全てのグラフを消去します\nいいですか？", title: "確認") else { return }
        doc.update("グラフの全削除") { p in
            var g = AppSettings.shared.defaultGraph(); g.name = "Untitled.SMP"
            p.graphs = [g]; p.dataFiles = [:]
        }
        doc.activeGraphIndex = 0
        doc.soloGraph = nil
        canvas.selection = []
    }

    /// グラフの読み込み: SMP のグラフをこの窓に足す(空の窓なら置き換える)
    @objc func importGraphs(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.message = "グラフ(SMP ファイル)を選んでください。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        loadGraphFile(url)
    }

    func loadGraphFile(_ url: URL) {
        guard let doc else { return }
        do {
            var p = try SMPReader.read(data: Data(contentsOf: url), fileName: url.lastPathComponent)
            Sma4Document.loadMissingData(&p, baseURL: url.deletingLastPathComponent())
            AppSettings.shared.noteRecent(url.path)
            let empty = doc.fileURL == nil && doc.project.graphs.count == 1 && doc.project.graphs[0].series.isEmpty
                && doc.project.graphs[0].objects.isEmpty && !doc.isDocumentEdited
            if empty {
                doc.replaceProjectWithoutUndo(p)
                doc.fileURL = url
                doc.fileType = Sma4Document.smpType
                doc.fileModificationDate = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                synchronizeWindowTitleWithDocumentName()
                checkMissingData()
                return
            }
            doc.update("グラフの読み込み") { proj in
                for (_, var file) in p.dataFiles {
                    let name = DataImport.uniqueName(file.name, contents: file, in: proj)
                    if name != file.name {
                        for gIndex in p.graphs.indices {
                            for sIndex in p.graphs[gIndex].series.indices where SMPProject.key(p.graphs[gIndex].series[sIndex].name) == SMPProject.key(file.name) {
                                p.graphs[gIndex].series[sIndex].name = name
                            }
                        }
                        file.name = name
                    }
                    proj.setDataFile(file)
                }
                proj.graphs.append(contentsOf: p.graphs.prefix(GraphWindowController.maxGraphs - proj.graphs.count))
            }
            doc.activeGraphIndex = doc.project.graphs.count - 1
            checkMissingData()
        } catch {
            MessageBox.show("不正なファイルです\n\(error.localizedDescription)", title: "エラー", style: .warning)
        }
    }

    @objc func openRecent(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: path) else {
            MessageBox.show("file not found\n\(path)", title: "エラー"); return
        }
        loadGraphFile(url)
    }

    @objc func saveGraphs(_ sender: Any?) { doc?.save(sender) }

    @objc func saveAllAs(_ sender: Any?) { doc?.saveAs(sender) }

    /// グラフの個別保存: 選択中のグラフだけを SMP にする
    @objc func saveActiveGraph(_ sender: Any?) {
        guard let doc, let g = doc.activeGraph else { return }
        if doc.project.graphs.count > 1 { MessageBox.show("現在選択中のグラフしかセーブしません", title: "Message") }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = g.name.uppercased().hasSuffix(".SMP") ? g.name : g.name + ".SMP"
        panel.allowedContentTypes = [UTType(exportedAs: Sma4Document.smpType)]
        let (accessory, withData) = SaveAccessory.make()
        panel.accessoryView = accessory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var p = SMPProject()
        var single = g
        single.name = url.lastPathComponent
        single.page.saveData = withData()
        p.graphs = [single]
        for s in g.series { if let f = doc.project.dataFile(named: s.name) { p.setDataFile(f) } }
        do {
            try SMPWriter.data(for: p).write(to: url)
            AppSettings.shared.noteRecent(url.path)
        } catch {
            MessageBox.show("File write error!\n\(error.localizedDescription)", title: "Error", style: .warning)
        }
    }

    @objc func saveAsDefault(_ sender: Any?) {
        guard let g = doc?.activeGraph else { return }
        do {
            try AppSettings.shared.saveAsDefault(g)
            AppSettings.shared.templatePath = nil
            setStatus("選択中のグラフをディフォルトの設定にしました")
        } catch {
            MessageBox.show("File write error!\n\(error.localizedDescription)", title: "Error", style: .warning)
        }
    }

    @objc func chooseTemplate(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.message = "テンプレートにする SMP ファイルを選んでください。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard (try? SMPReader.read(data: Data(contentsOf: url))) != nil else {
            MessageBox.show("不正なファイルです", title: "エラー"); return
        }
        AppSettings.shared.templatePath = url.path
        setStatus("テンプレートを設定しました: \(url.lastPathComponent)")
    }

    @objc func printGraphs(_ sender: Any?) {
        if doc?.project.graphs.count ?? 0 > 1 && doc?.soloGraph != nil {
            MessageBox.show("CRT上に表示されていない\nグラフも印刷されます", title: "確認")
        }
        doc?.printDocument(sender)
    }

    @objc func printerSetup(_ sender: Any?) { doc?.runPageLayout(sender) }

    /// 用紙設定(印刷サイズの設定)
    @objc func paperSetup(_ sender: Any?) {
        guard let doc, let g = doc.activeGraph, let page = GraphDialogs.printSize(page: g.page, over: window) else { return }
        doc.update("用紙設定") { p in for i in p.graphs.indices { p.graphs[i].page = page } }
        canvas.updateSize()
    }

    @objc func togglePreview(_ sender: Any?) {
        canvas.preview.toggle()
        canvas.updateSize()
        if !canvas.preview { canvas.scroll(.zero) }
        refreshStatus()
        validateToolbar()
    }

    @objc func exportPDF(_ sender: Any?) {
        guard let (r, rect) = exportRenderer() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = exportBaseName() + ".pdf"
        panel.allowedContentTypes = [.pdf]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try GraphExporter.pdfData(renderer: r, rect: rect).write(to: url) }
        catch { MessageBox.show("File write error!\n\(error.localizedDescription)", title: "Error") }
    }

    @objc func exportPNG(_ sender: Any?) {
        guard let (r, rect) = exportRenderer() else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = exportBaseName() + ".png"
        panel.allowedContentTypes = [.png]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let data = GraphExporter.pngData(renderer: r, rect: rect, dpi: AppSettings.shared.exportDPI) else { return }
        do { try data.write(to: url) } catch { MessageBox.show("File write error!\n\(error.localizedDescription)", title: "Error") }
    }

    func exportBaseName() -> String {
        guard let doc else { return "Graph" }
        return (doc.fileDisplayName as NSString).deletingPathExtension
    }

    func exportRenderer() -> (GraphRenderer, CGRect)? {
        guard let doc else { return nil }
        let r = doc.renderer()
        let m = AppSettings.shared.copyMargins
        var rect = r.contentBounds()
        rect = CGRect(x: rect.minX - m[0] * 100, y: rect.minY - m[1] * 100,
                      width: rect.width + (m[0] + m[2]) * 100, height: rect.height + (m[1] + m[3]) * 100)
        return (r, rect)
    }

    @objc func closeWindow(_ sender: Any?) { window?.performClose(sender) }

    @objc func quitAll(_ sender: Any?) { NSApp.terminate(sender) }

    // MARK: - データ

    @objc func openDataFile(_ sender: Any?) {
        guard let doc, let g = doc.activeGraph else { return }
        guard g.series.count < GraphWindowController.maxSeries else {
            MessageBox.show("\(GraphWindowController.maxSeries)個以上のファイルは開けません", title: "エラー"); return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.allowsMultipleSelection = true
        panel.message = "データファイルを選んでください(ワイルドカード: \(AppSettings.shared.wildcard))"
        guard panel.runModal() == .OK else { return }
        let urls = panel.urls.filter { Self.matches($0.lastPathComponent, wildcard: AppSettings.shared.wildcard) || panel.urls.count == 1 }
        addDataFiles(urls, showProperties: urls.count == 1)
    }

    static func matches(_ name: String, wildcard: String) -> Bool {
        let patterns = wildcard.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
        for p in patterns where !p.isEmpty {
            if p == "*.*" || p == "*" { return true }
            if fnmatch(p.lowercased(), name.lowercased(), 0) == 0 { return true }
        }
        return patterns.isEmpty
    }

    func addDataFiles(_ urls: [URL], showProperties: Bool) {
        guard let doc, !urls.isEmpty else { return }
        let prefs = AppSettings.shared.dataOpenPreferences
        var added: [Int] = []
        let graphIndex = gi
        var proj = doc.project
        for url in urls {
            guard proj.graphs[graphIndex].series.count < GraphWindowController.maxSeries else { break }
            guard let data = try? Data(contentsOf: url) else { continue }
            var file = DataImport.dataFile(name: url.lastPathComponent, contents: data, timestamp: SMPWriter.timestamp(Date()))
            file.name = DataImport.uniqueName(file.name, contents: file, in: proj)
            proj.setDataFile(file)
            let index = proj.graphs[graphIndex].series.count
            var s = DataImport.newSeries(name: file.name, path: url.path, index: index, preferences: prefs)
            if let prev = proj.graphs[graphIndex].series.last {
                // 前のデータの次の形・線にしていく
                if prefs.autoDotType { s.dotType = PlotType.next(after: prev.dotType) }
                if prefs.autoLineType, (1...5).contains(prev.lineType.rawValue) { s.lineType = LineType(code: prev.lineType.rawValue % 5 + 1) }
            }
            SeriesDefaults.apply(to: &s, fileName: file.name)
            if index > 0, prefs.autoDotType, let prev = proj.graphs[graphIndex].series.last { s.dotType = PlotType.next(after: prev.dotType) }
            DataImport.guessColumns(file, series: &s)
            s.linesRead = DataParser.rows(for: s, lines: file.lines).count
            proj.graphs[graphIndex].series.append(s)
            doc.noteDataFileDate(file.name, url: url)
            added.append(index)
        }
        var axes: [Int] = []
        if prefs.autoScaleX { axes.append(0) }
        if prefs.autoScaleY { axes.append(1) }
        if doc.project.graphs[graphIndex].series.isEmpty { axes = [0, 1] }
        GraphOps.clearScale(&proj, graphIndex: graphIndex, axes: axes)
        syncCommonAxes(&proj.graphs[graphIndex])
        let newProject = proj
        doc.update("データファイルを開く") { $0 = newProject }
        if showProperties, let i = added.first { showSeriesProperties(i) }
    }

    func syncCommonAxes(_ g: inout Graph) {
        if g.axes[0].commonWithOpposite { g.axes[2] = GraphDialogs.mirrored(g.axes[0], from: g.axes[2]) }
        if g.axes[1].commonWithOpposite { g.axes[3] = GraphDialogs.mirrored(g.axes[1], from: g.axes[3]) }
    }

    @objc func closeDataFile(_ sender: Any?) {
        guard let doc, let g = doc.activeGraph, !g.series.isEmpty else { return }
        if g.series.count == 1 {
            guard MessageBox.confirm("1個のファイルをCloseします", title: "Sma4 for Mac") else { return }
            doc.update(graph: gi, "データファイルを閉じる") { $0.series.removeAll(); $0.masks.removeAll() }
            doc.update("データファイルを閉じる") { GraphOps.pruneData(&$0) }
            return
        }
        runManager(title: "データの管理", okTitle: "OK")
    }

    @objc func showDataManager(_ sender: Any?) {
        guard let doc, let g = doc.activeGraph else { return }
        if g.series.isEmpty { openDataFile(sender); return }
        if g.series.count == 1 { showSeriesProperties(0); return }
        runManager(title: "データの管理", okTitle: "設定…", opensProperties: true)
        _ = doc
    }

    func runManager(title: String, okTitle: String, opensProperties: Bool = false) {
        guard let doc, let g = doc.activeGraph,
              let r = DataDialogs.manager(series: g.series, title: title, okTitle: okTitle, over: window) else { return }
        let graphIndex = gi
        let oldIDs = g.series.map(\.id)
        doc.update(r.series.count < g.series.count ? "データファイルを閉じる" : "Update") { p in
            p.graphs[graphIndex].series = r.series
            // Data Mask の番号を付け直す
            let newIndex = Dictionary(uniqueKeysWithValues: r.series.enumerated().map { ($0.element.id, $0.offset) })
            p.graphs[graphIndex].masks = p.graphs[graphIndex].masks.compactMap { m in
                guard m.seriesIndex < oldIDs.count, let n = newIndex[oldIDs[m.seriesIndex]] else { return nil }
                var mm = m; mm.seriesIndex = n; return mm
            }
            GraphOps.pruneData(&p)
        }
        if opensProperties, let e = r.propertyIndex { showSeriesProperties(e) }
    }

    func showSeriesProperties(_ index: Int, startPage: Int = 0) {
        guard let doc, let g = doc.activeGraph, index < g.series.count else { return }
        let s = g.series[index]
        let others = g.series.enumerated().filter { $0.offset != index }.map(\.element)
        guard var ns = DataDialogs.property(series: s, index: index, graph: g, project: doc.project, others: others,
                                            over: window, startPage: startPage) else { return }
        let graphIndex = gi
        if let file = doc.project.dataFile(named: ns.name) {
            ns.linesRead = DataParser.rows(for: ns, lines: file.lines).count
        }
        let final = ns
        doc.update(graph: graphIndex, "データのプロパティ") { $0.series[index] = final }
        if let msg = doc.plotData()[graphIndex][index].error {
            MessageBox.show(msg, title: "エラー", style: .warning)
        }
    }

    @objc func createDataFile(_ sender: Any?) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "NEW.DAT"
        panel.message = "新しいデータファイルの名前を決めてください。エディタで開きます。"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if !FileManager.default.fileExists(atPath: url.path) {
            try? "0 0\r\n".data(using: .utf8)?.write(to: url)
        }
        openInEditor(url)
        addDataFiles([url], showProperties: false)
        setStatus("エディタで保存したあと、再描画(F2)で読み直します")
    }

    @objc func toggleSeriesVisibility(_ sender: Any?) {
        guard let doc, let g = doc.activeGraph, !g.series.isEmpty else { return }
        let visible = IndexSet(g.series.indices.filter { g.series[$0].visible })
        guard let sel = ListDialogs.chooseMany(title: "表示するファイルの選択", items: g.series.map { DataDialogs.managerTitle($0) },
                                               selected: visible, over: window) else { return }
        doc.update(graph: gi, "表示/非表示切り替え") { graph in
            for i in graph.series.indices { graph.series[i].visible = sel.contains(i) }
        }
    }

    /// データファイルの編集: 設定のエディタで開く(SMP に埋め込まれたデータは一時ファイルにして開く)
    @objc func editDataFile(_ sender: Any?) {
        guard let doc, let g = doc.activeGraph,
              let si = chooseSeries("編集するファイル", where: { $0.kind != .function }) else { return }
        let s = g.series[si]
        var url = URL(fileURLWithPath: s.path)
        if !FileManager.default.fileExists(atPath: url.path) {
            guard let file = doc.project.dataFile(named: s.name) else { return }
            let dir = AppSettings.supportDirectory.appendingPathComponent("Temp", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            url = dir.appendingPathComponent(s.name)
            try? (file.lines.joined(separator: "\r\n") + "\r\n").data(using: .utf8)?.write(to: url)
            doc.update(graph: gi, "データファイルの編集") { $0.series[si].path = url.path }
        }
        doc.noteDataFileDate(s.name, url: url)
        openInEditor(url)
    }

    func openInEditor(_ url: URL) {
        let editor = AppSettings.shared.editorPath
        if !editor.isEmpty, FileManager.default.fileExists(atPath: editor) {
            let cfg = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.open([url], withApplicationAt: URL(fileURLWithPath: editor), configuration: cfg) { _, error in
                if let error { DispatchQueue.main.async { MessageBox.show("cannot open editor\n\(error.localizedDescription)", title: "Error") } }
            }
        } else if let textEdit = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.TextEdit") {
            NSWorkspace.shared.open([url], withApplicationAt: textEdit, configuration: NSWorkspace.OpenConfiguration())
        }
    }

    /// Save Data: 数式変換した後の値を保存する(TAB 区切りかカンマ区切り)
    @objc func saveData(_ sender: Any?) {
        guard let doc, let g = doc.activeGraph, let si = chooseSeries("セーブするデータの選択") else { return }
        let data = doc.plotData()[gi][si]
        let panel = NSSavePanel()
        panel.nameFieldStringValue = (g.series[si].name as NSString).deletingPathExtension + ".DAT"
        let (accessory, isTab) = DataDialogs.separatorAccessory(tab: AppSettings.shared.exportSeparatorTab)
        panel.accessoryView = accessory
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let tab = isTab()
        AppSettings.shared.exportSeparatorTab = tab
        var out = ""
        for i in 0..<min(data.x.count, data.y.count) {
            let x = data.x[i].isFinite ? String(format: "%+9e", data.x[i]) : " ERROR_VALUE "
            let y = data.y[i].isFinite ? String(format: "%+9e", data.y[i]) : " ERROR_VALUE "
            out += x + (tab ? "\t" : ",") + y + "\r\n"
        }
        do { try out.data(using: .utf8)?.write(to: url) } catch { MessageBox.show("File write error!", title: "Error") }
    }

    @objc func toggleReadValue(_ sender: Any?) {
        if canvas.mode == .readValue {
            canvas.mode = .normal
            return
        }
        guard let g = doc?.activeGraph, !g.series.isEmpty, let si = chooseSeries("値を読むファイルの選択") else { return }
        readValueSeries = si
        canvas.mode = .readValue
        canvas.readMark = nil
        canvas.setReadValue(series: si, index: 0)
        let panel = ReadValuePanel(controller: self)
        readValuePanel = panel
        panel.show()
        readValueChanged()
    }

    /// Data Mask: マスクする範囲をマウスで囲む
    @objc func dataMask(_ sender: Any?) {
        guard let doc, let g = doc.activeGraph, !g.series.isEmpty else { return }
        if !g.masks.isEmpty {
            guard let choice = DataDialogs.maskChoice(masks: g.masks, names: g.series.map(\.displayName), over: window) else { return }
            if case .delete(let i) = choice {
                doc.update(graph: gi, "Data Mask の削除") { $0.masks.remove(at: i) }
                return
            }
        }
        guard g.masks.count < 20 else { MessageBox.show("これ以上のマスク領域は設定できません", title: "エラー"); return }
        canvas.mode = .dataMask
        setStatus("データマスク: 隠す範囲を左ボタンで囲んでください(esc で中止)")
    }

    func applyDataMask(pageRect r: CGRect) {
        guard let doc, let g = doc.activeGraph else { return }
        let t = GraphRenderer.graphTransform(g).inverted()
        let a = CGPoint(x: r.minX, y: r.minY).applying(t), b = CGPoint(x: r.maxX, y: r.maxY).applying(t)
        let fr = GraphRenderer.Frame(g)
        let names = g.series.map { DataDialogs.managerTitle($0) }
        guard let sel = ListDialogs.chooseMany(title: "Select files for data masking", items: names,
                                               selected: IndexSet(g.series.indices), over: window), !sel.isEmpty else { return }
        doc.update(graph: gi, "Data Mask") { graph in
            for si in sel where graph.masks.count < 20 {
                let s = graph.series[si]
                let h = graph.horizontalAxisIndex(for: s), v = graph.verticalAxisIndex(for: s)
                let x0 = fr.scales[h].value(atFraction: Double(a.x) / fr.width), x1 = fr.scales[h].value(atFraction: Double(b.x) / fr.width)
                let y0 = fr.scales[v].value(atFraction: 1 - Double(b.y) / fr.height), y1 = fr.scales[v].value(atFraction: 1 - Double(a.y) / fr.height)
                graph.masks.append(DataMask(seriesIndex: si, xMin: min(x0, x1), xMax: max(x0, x1), yMin: min(y0, y1), yMax: max(y0, y1)))
            }
        }
    }

    // MARK: - 編集

    /// 図面コピー(コピー領域の設定のあと、PDF と PNG をクリップボードへ)
    @objc func copy(_ sender: Any?) { copyFigure(sender) }

    @objc func copyFigure(_ sender: Any?) {
        guard let doc else { return }
        if doc.soloGraph != nil && doc.project.graphs.count > 1 {
            MessageBox.show("CRT上に表示されていない\nグラフもコピーされます", title: "確認")
        }
        let r = doc.renderer(visibleOnly: false)
        let b = r.contentBounds()
        let bounds = CGRect(x: b.minX / 100, y: b.minY / 100, width: b.width / 100, height: b.height / 100)
        guard let c = GraphDialogs.clipRegion(bounds: bounds, over: window) else { return }
        let rect = CGRect(x: b.minX - c.margins[0] * 100, y: b.minY - c.margins[1] * 100,
                          width: b.width + (c.margins[0] + c.margins[2]) * 100, height: b.height + (c.margins[1] + c.margins[3]) * 100)
        putFigureOnPasteboard(renderer: r, rect: rect, scale: c.scale / 100)
    }

    func putFigureOnPasteboard(renderer r: GraphRenderer, rect: CGRect, scale: Double = 1) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setData(GraphExporter.pdfData(renderer: r, rect: rect, scale: scale), forType: .pdf)
        if let png = GraphExporter.pngData(renderer: r, rect: rect, dpi: AppSettings.shared.exportDPI * scale) {
            pb.setData(png, forType: .png)
            if let img = NSImage(data: png), let tiff = img.tiffRepresentation { pb.setData(tiff, forType: .tiff) }
        }
        setStatus("図面をクリップボードにコピーしました")
    }

    /// データコピー: 数式変換したあとの (x, y) をクリップボードへ
    @objc func copyData(_ sender: Any?) {
        guard let doc, let si = chooseSeries("クリップボードへコピーするデータの選択") else { return }
        let data = doc.plotData()[gi][si]
        var out = ""
        for i in 0..<min(data.x.count, data.y.count) where data.x[i].isFinite && data.y[i].isFinite {
            out += String(format: "%+9e", data.x[i]) + "\t" + String(format: "%+9e", data.y[i]) + "\r\n"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
        setStatus("データをクリップボードにコピーしました")
    }

    /// データ貼付け: クリップボードの文字のデータをファイルにしてグラフにする
    @objc func pasteData(_ sender: Any?) {
        guard let doc, let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            MessageBox.show("クリップボードに文字のデータがありません。"); return
        }
        var name = "NEW.DAT"
        var k = 1
        while doc.project.dataFile(named: name) != nil { k += 1; name = "NEW\(k).DAT" }
        let file = DataImport.dataFile(name: name, contents: Data(text.utf8), timestamp: SMPWriter.timestamp(Date()))
        let graphIndex = gi
        var proj = doc.project
        proj.setDataFile(file)
        let index = proj.graphs[graphIndex].series.count
        var s = DataImport.newSeries(name: name, path: name, index: index, preferences: AppSettings.shared.dataOpenPreferences)
        if let prev = proj.graphs[graphIndex].series.last, AppSettings.shared.autoDotType { s.dotType = PlotType.next(after: prev.dotType) }
        DataImport.guessColumns(file, series: &s)
        s.linesRead = DataParser.rows(for: s, lines: file.lines).count
        proj.graphs[graphIndex].series.append(s)
        GraphOps.clearScale(&proj, graphIndex: graphIndex, axes: [0, 1])
        syncCommonAxes(&proj.graphs[graphIndex])
        let final = proj
        doc.update("データ貼付け") { $0 = final }
    }

    @objc func undoAction(_ sender: Any?) {
        guard let um = doc?.undoManager, um.canUndo else { return }
        um.undo()
        canvas.needsDisplay = true
    }

    func selectedItems() -> [ObjectItem] {
        guard let g = doc?.activeGraph else { return [] }
        return g.objects.filter { canvas.selection.contains($0.id) }
    }

    func selectedTexts() -> [ObjectItem] {
        selectedItems().filter { if case .text = $0.object { return true } else { return false } }
    }

    /// コピー(矢印・文字などのオブジェクト)
    @objc func copyObject(_ sender: Any?) {
        let items = selectedItems()
        guard !items.isEmpty else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(SMPWriter.legendLines(items.map(\.object)).joined(separator: "\n"), forType: GraphWindowController.objectPasteboardType)
        let plain = items.compactMap { item -> String? in
            if case .text(let t) = item.object { return RichTextParser.plainText(t.text) } else { return nil }
        }
        if !plain.isEmpty { pb.setString(plain.joined(separator: "\n"), forType: .string) }
    }

    /// 切り抜き(複数選んでいるときは働かない)
    @objc func cutObject(_ sender: Any?) {
        guard canvas.selection.count == 1 else { return }
        copyObject(sender)
        delete(sender)
    }

    @objc func paste(_ sender: Any?) {
        guard let doc else { return }
        let pb = NSPasteboard.general
        if let s = pb.string(forType: GraphWindowController.objectPasteboardType) {
            let objects = SMPReader.legendObjects(lines: s.components(separatedBy: "\n"))
            guard !objects.isEmpty else { return }
            let items = objects.map { ObjectItem(offset($0, by: 300)) }
            doc.update(graph: gi, "貼り付け") { $0.objects.append(contentsOf: items) }
            canvas.selection = Set(items.map(\.id))
        }
    }

    func offset(_ o: GraphObject, by d: Int) -> GraphObject {
        switch o {
        case .text(var t): t.x += d; t.y += d; return .text(t)
        case .dot(var p): p.x += d; p.y += d; return .dot(p)
        case .shape(var s):
            if s.xReference == 0 { s.x1 += Double(d) / 100; s.x2 += Double(d) / 100 }
            if s.yReference == 0 { s.y1 += Double(d) / 100; s.y2 += Double(d) / 100 }
            return .shape(s)
        case .picture(var p):
            p.shape.x1 += Double(d) / 100; p.shape.x2 += Double(d) / 100
            p.shape.y1 += Double(d) / 100; p.shape.y2 += Double(d) / 100
            return .picture(p)
        case .raw: return o
        }
    }

    @objc func delete(_ sender: Any?) {
        guard let doc, !canvas.selection.isEmpty else { return }
        let ids = canvas.selection
        doc.update(graph: gi, "削除") { $0.objects.removeAll { ids.contains($0.id) } }
        canvas.selection = []
    }

    @objc override func selectAll(_ sender: Any?) {
        guard let g = doc?.activeGraph else { return }
        canvas.selection = Set(g.objects.map(\.id))
    }

    /// 上に(選んだものを手前へ)・下に(後ろへ)
    @objc func bringForward(_ sender: Any?) {
        guard let doc, !canvas.selection.isEmpty else { return }
        let ids = canvas.selection
        doc.update(graph: gi, "上に") { g in
            let moving = g.objects.filter { ids.contains($0.id) }
            g.objects.removeAll { ids.contains($0.id) }
            g.objects.append(contentsOf: moving)
        }
    }

    @objc func sendBackward(_ sender: Any?) {
        guard let doc, !canvas.selection.isEmpty else { return }
        let ids = canvas.selection
        doc.update(graph: gi, "下に") { g in
            let moving = g.objects.filter { ids.contains($0.id) }
            g.objects.removeAll { ids.contains($0.id) }
            g.objects.insert(contentsOf: moving, at: 0)
        }
    }

    // MARK: - グラフ

    @objc func showAxisDialog(_ sender: Any?) {
        let tag = (sender as? NSMenuItem)?.tag ?? 0
        showAxis(tag)
    }

    func showAxis(_ index: Int, startPage: Int = 0) {
        guard let doc, let g = doc.activeGraph,
              let ng = GraphDialogs.axis(index, graph: g, over: window, startPage: startPage) else { return }
        doc.update(graph: gi, ["X-Axis", "Y-Axis", "U-Axis", "R-Axis"][index]) { $0 = ng }
    }

    @objc func clearAllScale(_ sender: Any?) {
        guard let doc, let g = doc.activeGraph else { return }
        var axes = [0, 1]
        if g.uIndependent { axes.append(2) }
        if g.rIndependent { axes.append(3) }
        let graphIndex = gi
        doc.update("Clear All Scale") { p in
            GraphOps.clearScale(&p, graphIndex: graphIndex, axes: axes)
            self.syncCommonAxes(&p.graphs[graphIndex])
        }
    }

    @objc func clearScale(_ sender: Any?) {
        guard let doc else { return }
        let tag = (sender as? NSMenuItem)?.tag ?? 0
        let graphIndex = gi
        doc.update("Clear Scale") { p in
            GraphOps.clearScale(&p, graphIndex: graphIndex, axes: [tag])
            self.syncCommonAxes(&p.graphs[graphIndex])
        }
    }

    @objc func beginTrimming(_ sender: Any?) {
        if canvas.mode == .trimming { canvas.mode = .normal; return }
        canvas.mode = .trimming
        setStatus("トリミング: 新しいスケールにする範囲を左ボタンで囲んでください(esc で中止)")
    }

    func applyTrimming(pageRect r: CGRect) {
        guard let doc, let g = doc.activeGraph else { return }
        let t = GraphRenderer.graphTransform(g).inverted()
        let a = CGPoint(x: r.minX, y: r.minY).applying(t), b = CGPoint(x: r.maxX, y: r.maxY).applying(t)
        let fr = GraphRenderer.Frame(g)
        func hv(_ x: CGFloat, _ axis: Int) -> Double { fr.scales[axis].value(atFraction: Double(x) / fr.width) }
        func vv(_ y: CGFloat, _ axis: Int) -> Double { fr.scales[axis].value(atFraction: 1 - Double(y) / fr.height) }
        let ranges: [(Bool, Double, Double)] = [
            (true, hv(a.x, 0), hv(b.x, 0)),
            (true, vv(b.y, 1), vv(a.y, 1)),
            (g.uIndependent, hv(a.x, 2), hv(b.x, 2)),
            (g.rIndependent, vv(b.y, 3), vv(a.y, 3)),
        ]
        guard let result = GraphDialogs.trimming(ranges: ranges, over: window) else { return }
        doc.update(graph: gi, "トリミング") { graph in
            for (axis, r) in result.enumerated() where r.0 {
                graph.axes[axis].from = r.1
                graph.axes[axis].to = r.2
                if graph.axes[axis].autoStep {
                    let auto = AxisScale.autoScaled(graph.axes[axis], minValue: min(r.1, r.2), maxValue: max(r.1, r.2))
                    graph.axes[axis].increment = auto.increment
                    graph.axes[axis].division = auto.division
                }
            }
            self.syncCommonAxes(&graph)
        }
    }

    @objc func showFrameDialog(_ sender: Any?) { showGraphPropertySheet(page: 0) }

    @objc func showGraphProperty(_ sender: Any?) { showGraphPropertySheet(page: 1) }

    func showGraphPropertySheet(page: Int) {
        guard let doc, let g = doc.activeGraph, let ng = GraphDialogs.graphProperty(graph: g, over: window, startPage: page) else { return }
        doc.update(graph: gi, page == 0 ? "Frame" : "グラフのプロパティ") { $0 = ng }
    }

    @objc func showAllGraphs(_ sender: Any?) {
        doc?.soloGraph = nil
        canvas.needsDisplay = true
    }

    @objc func showActiveGraphOnly(_ sender: Any?) {
        guard let doc else { return }
        doc.soloGraph = doc.activeGraphIndex
        canvas.needsDisplay = true
    }

    @objc func selectGraph(_ sender: NSMenuItem) {
        guard let doc, sender.tag < doc.project.graphs.count else { return }
        doc.activeGraphIndex = sender.tag
        if doc.soloGraph != nil { doc.soloGraph = sender.tag }
        canvas.selection = []
        canvas.needsDisplay = true
    }

    // MARK: - 挿入

    /// tag: 4 X軸 5 Y軸 6 U軸 7 R軸 8 その他
    @objc func insertTitle(_ sender: Any?) {
        let tag = (sender as? NSMenuItem)?.tag ?? 8
        let kind = TextObject.Kind(rawValue: tag) ?? .other
        if kind != .other, let g = doc?.activeGraph,
           let item = g.objects.first(where: { if case .text(let t) = $0.object { return t.kind == kind } else { return false } }) {
            editObject(item.id)
            return
        }
        insertText(kind: kind, text: "")
    }

    @objc func insertOtherText(_ sender: Any?) { insertText(kind: .other, text: "") }

    func newText(kind: TextObject.Kind, graph g: Graph) -> TextObject {
        var t = TextObject()
        t.kind = kind
        t.latinFont = LogFont.latinDefault(points: 24)
        t.japaneseFont = LogFont.japaneseDefault(points: 24)
        t.symbolFont = LogFont.symbolDefault(points: 24)
        if kind == .xTitle || kind == .yTitle || kind == .uTitle || kind == .rTitle {
            t.latinFont.isBold = true
        }
        switch kind {
        case .xTitle: t.x = g.width / 2 - 1500; t.y = g.height + 1600
        case .yTitle: t.x = -1300; t.y = g.height / 2 + 2000; t.angle = 90
        case .uTitle: t.x = g.width / 2 - 1500; t.y = -1200
        case .rTitle: t.x = g.width + 2200; t.y = g.height / 2 + 2000; t.angle = 90
        case .other: t.x = 1000; t.y = 1500
        }
        if let d = AppSettings.shared.stored("title.\(kind.rawValue)", as: ObjectDialogs.TitleDefaults.self) { d.apply(&t) }
        return t
    }

    func insertText(kind: TextObject.Kind, text: String) {
        guard let doc, let g = doc.activeGraph else { return }
        var t = newText(kind: kind, graph: g)
        t.text = text.replacingOccurrences(of: "\r\n", with: "\\n").replacingOccurrences(of: "\n", with: "\\n")
        let graphIndex = gi
        guard let r = ObjectDialogs.text(t, title: kind.title, isNew: true, over: window) else { return }
        if case .placeWithMouse(let nt) = r {
            // マウスの所に枠が出て、クリックした位置が文字の開始の左下になる
            canvas.placingText = nt
            canvas.mode = .placeText
            setStatus("文字列を書く位置で左クリックしてください(esc で中止)")
            canvas.onPlaced = { [weak self] p, _ in
                guard let self, let doc = self.doc, graphIndex < doc.project.graphs.count else { return }
                var tt = nt
                let graph = doc.project.graphs[graphIndex]
                if tt.absolutePosition {
                    tt.x = Int(p.x); tt.y = Int(p.y)
                } else {
                    let local = p.applying(GraphRenderer.graphTransform(graph).inverted())
                    tt.x = Int(self.canvas.snapped(local.x)); tt.y = Int(self.canvas.snapped(local.y))
                }
                let item = ObjectItem(.text(tt))
                doc.update(graph: graphIndex, kind.title) { $0.objects.append(item) }
                self.canvas.selection = [item.id]
            }
        }
    }

    @objc func pasteTextFromClipboard(_ sender: Any?) {
        guard let text = NSPasteboard.general.string(forType: .string), !text.isEmpty else {
            MessageBox.show("クリップボードに文字がありません。"); return
        }
        insertText(kind: .other, text: text)
    }

    /// 凡例: データのファイル名とドットの見本(%01E%01N)
    @objc func insertLegend(_ sender: Any?) {
        guard let doc, let g = doc.activeGraph, !g.series.isEmpty else { return }
        guard let sel = ListDialogs.chooseMany(title: "凡例をつけるメモリー", items: g.series.map { DataDialogs.managerTitle($0) },
                                               selected: IndexSet(g.series.indices), over: window), !sel.isEmpty else { return }
        let indices = Array(sel)
        let curves = indices.map { g.series[$0].kind.hasCurve && g.series[$0].dotType == 0 }
        insertText(kind: .other, text: GraphOps.legendText(seriesIndices: indices, useCurve: curves).replacingOccurrences(of: "\\n", with: "\n"))
    }

    /// 0:左端 1:両端(中央) 2:右端
    @objc func alignTexts(_ sender: Any?) {
        guard let doc else { return }
        let tag = (sender as? NSMenuItem)?.tag ?? 0
        let renderer = doc.renderer()
        let env = renderer.environment(for: gi)
        let items = selectedTexts()
        guard items.count >= 2 else { return }
        var spans: [UUID: (CGFloat, CGFloat)] = [:]
        for item in items {
            if case .text(let t) = item.object {
                let w = renderer.textLayout(t, env: env).bounds.width
                spans[item.id] = (CGFloat(t.x), CGFloat(t.x) + w)
            }
        }
        let lefts = spans.values.map(\.0), rights = spans.values.map(\.1)
        let target: CGFloat
        switch tag {
        case 1: target = ((lefts.min() ?? 0) + (rights.max() ?? 0)) / 2
        case 2: target = rights.max() ?? 0
        default: target = lefts.min() ?? 0
        }
        doc.update(graph: gi, "位置あわせ") { graph in
            for (k, item) in graph.objects.enumerated() {
                guard let span = spans[item.id], case .text(var t) = item.object else { continue }
                let w = span.1 - span.0
                switch tag {
                case 1: t.x = Int(target - w / 2)
                case 2: t.x = Int(target - w)
                default: t.x = Int(target)
                }
                graph.objects[k].object = .text(t)
            }
        }
    }

    @objc func insertArrow(_ sender: Any?) {
        var s = ShapeObject()
        s.objectType = 0; s.shapeType = 0
        s.x1 = 20; s.y1 = 20; s.x2 = 40; s.y2 = 35
        s.length = 500; s.width = 40; s.headMode = 1; s.headOpen = 30; s.headClose = 100
        if let d = AppSettings.shared.stored("arrow", as: ObjectDialogs.ShapeDefaults.self) { d.apply(&s, arrow: true) }
        editShape(s, id: nil)
    }

    @objc func insertBox(_ sender: Any?) {
        var s = ShapeObject()
        s.objectType = 3; s.shapeType = 3
        s.x1 = 10; s.y1 = 10; s.x2 = 60; s.y2 = 30
        s.length = 0; s.width = 40
        s.shadowColor = .black
        if let d = AppSettings.shared.stored("rect", as: ObjectDialogs.ShapeDefaults.self) { d.apply(&s, arrow: false) }
        editShape(s, id: nil)
    }

    func editShape(_ s: ShapeObject, id: UUID?) {
        guard let doc else { return }
        let graphIndex = gi
        let title = s.isBox ? "枠" : "矢印"
        let r = s.isBox ? ObjectDialogs.box(s, isNew: id == nil, over: window) : ObjectDialogs.arrow(s, isNew: id == nil, over: window)
        guard let r else { return }
        func store(_ ns: ShapeObject) {
            if let id {
                doc.update(graph: graphIndex, title) { g in
                    if let k = g.objects.firstIndex(where: { $0.id == id }) { g.objects[k].object = .shape(ns) }
                }
            } else {
                let item = ObjectItem(.shape(ns))
                doc.update(graph: graphIndex, title) { $0.objects.append(item) }
                canvas.selection = [item.id]
            }
        }
        switch r {
        case .ok(let ns): store(ns)
        case .delete:
            if let id { doc.update(graph: graphIndex, "削除") { $0.objects.removeAll { $0.id == id } } }
        case .placeWithMouse(let ns):
            // 貼付・位置をマウスで設定: 始点でボタンを押し、終点で放す
            canvas.placingShape = ns
            canvas.mode = .placeShape
            setStatus(ns.isBox ? "枠の角から対角の角までドラッグしてください" : "矢印の始点から先端までドラッグしてください")
            canvas.onPlaced = { [weak self] a, b in
                guard let self, let doc = self.doc, graphIndex < doc.project.graphs.count else { return }
                let graph = doc.project.graphs[graphIndex]
                let t = GraphRenderer.graphTransform(graph).inverted()
                var s2 = ns
                self.canvas.setShapeEnd(&s2, end: 0, local: a.applying(t), graph: graph)
                self.canvas.setShapeEnd(&s2, end: 1, local: b.applying(t), graph: graph)
                store(s2)
            }
        }
    }

    @objc func insertDot(_ sender: Any?) {
        var d = DotObject()
        d.x = 3000; d.y = 2000
        d.dotType = PlotType.defaultCode
        editDot(d, id: nil)
    }

    func editDot(_ d: DotObject, id: UUID?) {
        guard let doc, let r = ObjectDialogs.dot(d, isNew: id == nil, over: window) else { return }
        let graphIndex = gi
        func store(_ nd: DotObject) {
            if let id {
                doc.update(graph: graphIndex, "Dot") { g in
                    if let k = g.objects.firstIndex(where: { $0.id == id }) { g.objects[k].object = .dot(nd) }
                }
            } else {
                let item = ObjectItem(.dot(nd))
                doc.update(graph: graphIndex, "Dot") { $0.objects.append(item) }
                canvas.selection = [item.id]
            }
        }
        switch r {
        case .ok(let nd): store(nd)
        case .delete:
            if let id { doc.update(graph: graphIndex, "削除") { $0.objects.removeAll { $0.id == id } } }
        case .placeWithMouse(let nd):
            canvas.placingDot = nd
            canvas.mode = .placeDot
            setStatus("Dot を置く位置で左クリックしてください(esc で中止)")
            canvas.onPlaced = { [weak self] p, _ in
                guard let self, let doc = self.doc, graphIndex < doc.project.graphs.count else { return }
                let graph = doc.project.graphs[graphIndex]
                let local = p.applying(GraphRenderer.graphTransform(graph).inverted())
                var d2 = nd
                d2.x = Int(local.x); d2.y = Int(local.y)
                store(d2)
            }
        }
    }

    @objc func insertPicture(_ sender: Any?) {
        var pic = PictureObject(path: "")
        pic.shape.objectType = 10
        pic.shape.x1 = 10; pic.shape.y1 = 10; pic.shape.x2 = 60; pic.shape.y2 = 40
        editPicture(pic, id: nil)
    }

    func editPicture(_ pic: PictureObject, id: UUID?) {
        guard let doc else { return }
        let resolver = doc.pictureResolver()
        guard let r = ObjectDialogs.picture(pic, isNew: id == nil, imageSize: { path in
            guard let img = resolver(path) else { return nil }
            return CGSize(width: img.width, height: img.height)
        }, over: window) else { return }
        let graphIndex = gi
        switch r {
        case .ok(let np):
            if let id {
                doc.update(graph: graphIndex, "図") { g in
                    if let k = g.objects.firstIndex(where: { $0.id == id }) { g.objects[k].object = .picture(np) }
                }
            } else {
                let item = ObjectItem(.picture(np))
                doc.update(graph: graphIndex, "図") { $0.objects.append(item) }
                canvas.selection = [item.id]
            }
        case .delete:
            if let id { doc.update(graph: graphIndex, "削除") { $0.objects.removeAll { $0.id == id } } }
        case .placeWithMouse: break
        }
    }

    /// 並べ替え: オブジェクトの描く順番(Object manager)
    @objc func reorderObjects(_ sender: Any?) {
        guard let doc, let g = doc.activeGraph, !g.objects.isEmpty else { return }
        let dlg = Dialog(.dataManager, title: "オブジェクトの順番")
        let p = dlg.page
        p.setText(IDC.ok, "設定…")
        var list = g.objects
        func title(_ o: GraphObject) -> String {
            switch o {
            case .text(let t): return "title: " + RichTextParser.plainText(t.text)
            case .dot(let d): return String(format: "point: (%5.1lf,%5.1lf)", Double(d.x) / 100, Double(d.y) / 100)
            case .shape(let s): return s.isBox ? String(format: "枠: (%5.1lf,%5.1lf)-(%5.1lf,%5.1lf)", s.x1, s.y1, s.x2, s.y2)
                                              : String(format: "arrow: (%5.1lf,%5.1lf)-(%5.1lf,%5.1lf)", s.x1, s.y1, s.x2, s.y2)
            case .picture(let pic): return "図: " + (pic.path as NSString).lastPathComponent
            case .raw(let t, _): return "type \(t)"
            }
        }
        guard let lb = p.list(561) else { return }
        func reload(_ sel: IndexSet) { lb.items = list.map { title($0.object) }; lb.selectedIndexes = sel }
        reload(list.isEmpty ? [] : [0])
        dlg.buttons[787] = {
            let sel = lb.selectedIndexes
            let moving = sel.map { list[$0] }
            for i in sel.reversed() { list.remove(at: i) }
            list.append(contentsOf: moving)
            reload(IndexSet((list.count - moving.count)..<list.count)); return false
        }
        dlg.buttons[788] = {
            let sel = lb.selectedIndexes
            let moving = sel.map { list[$0] }
            for i in sel.reversed() { list.remove(at: i) }
            list.insert(contentsOf: moving, at: 0)
            reload(IndexSet(0..<moving.count)); return false
        }
        dlg.buttons[789] = {
            let sel = lb.selectedIndexes
            for i in sel.reversed() { list.remove(at: i) }
            reload([]); return false
        }
        dlg.buttons[768] = { lb.selectedIndexes = IndexSet(0..<list.count); return false }
        guard dlg.run(over: window) == IDC.ok else { return }
        let final = list
        doc.update(graph: gi, "並べ替え") { $0.objects = final }
        if lb.selectedIndexes.count == 1, let i = lb.selectedIndexes.first, i < final.count { editObject(final[i].id) }
    }

    func editObject(_ id: UUID) {
        guard let doc, let g = doc.activeGraph, let item = g.objects.first(where: { $0.id == id }) else { return }
        let graphIndex = gi
        switch item.object {
        case .text(let t):
            guard let r = ObjectDialogs.text(t, title: t.kind.title, isNew: false, over: window) else { return }
            switch r {
            case .ok(let nt):
                doc.update(graph: graphIndex, t.kind.title) { g in
                    if let k = g.objects.firstIndex(where: { $0.id == id }) { g.objects[k].object = .text(nt) }
                }
            case .delete:
                doc.update(graph: graphIndex, "削除") { $0.objects.removeAll { $0.id == id } }
            case .placeWithMouse: break
            }
        case .shape(let s): editShape(s, id: id)
        case .dot(let d): editDot(d, id: id)
        case .picture(let p): editPicture(p, id: id)
        case .raw:
            MessageBox.show("このオブジェクトはこのアプリでは編集できません。\n保存するとそのまま残ります。")
        }
    }

    @objc func editSelected(_ sender: Any?) {
        if let id = canvas.selection.first { editObject(id) }
    }

    // MARK: - 解析

    /// tag: 1 多項式 4 指数 5 対数 6 べき 7 一般関数
    @objc func leastSquares(_ sender: Any?) {
        let tag = (sender as? NSMenuItem)?.tag ?? 1
        let kind = Series.Kind(rawValue: tag) ?? .polynomialLSQ
        guard let si = chooseSeries("最小二乗するファイルの選択", where: { $0.kind != .function }) else { return }
        runCurveSetup(seriesIndex: si, kind: kind, splineMode: nil)
    }

    @objc func spline(_ sender: Any?) {
        let tag = (sender as? NSMenuItem)?.tag ?? 0
        guard let si = chooseSeries("スプライン補間するファイルの選択", where: { $0.kind != .function }) else { return }
        runCurveSetup(seriesIndex: si, kind: .spline, splineMode: Spline.Mode(rawValue: tag) ?? .cubic)
    }

    func prepareCurve(_ s0: Series, kind: Series.Kind, graph g: Graph, data: SeriesPlotData) -> Series {
        var s = s0
        let xs = data.finitePoints.map(\.0)
        if s.kind != kind || (s.curveStart == 0 && s.curveEnd == 0) {
            s.curveStart = xs.min() ?? g.axes[0].from
            s.curveEnd = xs.max() ?? g.axes[0].to
            CurvePage.applyDefaults(&s)
        }
        if s.kind != kind && kind == .polynomialLSQ {
            s.lsqOrder = AppSettings.shared.stored("lsq.dimension", as: Int.self) ?? 1
        }
        s.kind = kind
        s.kindRaw = kind.rawValue
        if s.curveDivisions <= 0 { s.curveDivisions = 101 }
        if g.axes[0].scaleType.isLog && s.curveSpacing == .linear { s.curveSpacing = .exponential }
        return s
    }

    func runCurveSetup(seriesIndex si: Int, kind: Series.Kind, splineMode: Spline.Mode?) {
        guard let doc, let g = doc.activeGraph, si < g.series.count else { return }
        var s = prepareCurve(g.series[si], kind: kind, graph: g, data: doc.plotData()[gi][si])
        if let m = splineMode { s.lsqOrder = m.rawValue }
        s.extensionAnalysis = nil
        guard let ns = AnalysisDialogs.leastSquares(series: s, over: window) else { return }
        doc.update(graph: gi, kind == .spline ? "スプライン補間" : "最小二乗") { $0.series[si] = ns }
        showResult(seriesIndex: si)
    }

    /// 結果(最小二乗の結果)。失敗したときはそのことを知らせる
    func showResult(seriesIndex si: Int) {
        guard let doc else { return }
        let data = doc.plotData()
        guard gi < data.count, si < data[gi].count else { return }
        let d = data[gi][si]
        let s = doc.project.graphs[gi].series[si]
        if let e = d.error {
            let what = s.kind == .spline ? "スプライン" : (s.extensionAnalysis?.menuTitle ?? "最小二乗法")
            MessageBox.show("\(s.displayName)の \(what) に失敗しました\n\(e)", title: "エラー", style: .warning)
            return
        }
        guard s.kind != .spline else { return }
        let lines = d.resultLines.isEmpty ? (d.fit?.summary.components(separatedBy: "\n") ?? []) : d.resultLines
        guard !lines.isEmpty else { return }
        if AnalysisDialogs.information(title: s.displayName + DataDialogs.kindSuffix(s), lines: lines, over: window) == .new {
            insertText(kind: .other, text: lines.joined(separator: "\n"))
        }
    }

    /// 値評価: 最小二乗の結果の関数で、x に対する y を求める
    @objc func evaluateFit(_ sender: Any?) {
        guard let doc, let si = chooseSeries("最小二乗フィットによる値評価するファイルの選択", where: { $0.kind.isLSQ }) else { return }
        guard let fit = doc.plotData()[gi][si].fit else { return }
        var x = "0"
        while let input = ListDialogs.input(title: "最小二乗による値評価", prompt: "Ｘ値:", text: x, over: window) {
            x = input
            guard let v = Double(input.trimmingCharacters(in: .whitespaces)) ?? (try? Expression(input).evaluateScalar()) else { continue }
            let y = fit.evaluate(v)
            if !MessageBox.confirm("x = \(Num.g(v))\ny = \(Num.g(y))", title: "確認", yes: "もう一度", no: "閉じる") { break }
        }
    }

    @objc func aboutDLL(_ sender: Any?) {
        MessageBox.show("そのほかの解析では、次のことができます。\n"
                        + ExtensionAnalysis.allCases.map(\.menuTitle).joined(separator: "\n")
                        , title: "そのほかの解析について")
    }

    /// 特殊処理(Gaussian fitting など)。tag は ExtensionAnalysis の並びの番号
    @objc func extensionAnalysis(_ sender: Any?) {
        let tag = (sender as? NSMenuItem)?.tag ?? 0
        guard tag < ExtensionAnalysis.allCases.count, let doc, let g = doc.activeGraph else { return }
        let a = ExtensionAnalysis.allCases[tag]
        guard let si = chooseSeries("「\(a.menuTitle)」に使うデータを選ぶ", where: { $0.kind != .function }) else { return }
        let data = doc.plotData()[gi][si]
        var s = g.series[si]
        if a.usesFittingDialog {
            s = prepareCurve(s, kind: .extension1, graph: g, data: data)
            let pts = data.finitePoints
            var f = s.extensionAnalysis == a ? s.peakFit : PeakFitSettings.initialGuess(x: pts.map(\.0), y: pts.map(\.1), count: s.peakFit.count)
            guard let nf = AnalysisDialogs.fittingCondition(f, over: window) else { return }
            f = nf
            s.peakFit = f
            s.extensionAnalysis = a
            guard let ns = AnalysisDialogs.leastSquares(series: s, over: window) else { return }
            s = ns
        } else {
            s.kind = .extension1
            s.kindRaw = Series.Kind.extension1.rawValue
            s.extensionAnalysis = a
            if a == .smoothing { CurvePage.applyDefaults(&s) }
        }
        let final = s
        doc.update(graph: gi, a.menuTitle) { $0.series[si] = final }
        showResult(seriesIndex: si)
    }

    /// もう一度: 最小二乗・スプラインの条件を設定し直す
    @objc func reanalyze(_ sender: Any?) {
        guard let doc, let g = doc.activeGraph else { return }
        guard let si = chooseSeries("もう一度設定する最小二乗、スプラインの選択", where: { $0.kind.hasCurve || $0.extensionAnalysis != nil }) else { return }
        let s = g.series[si]
        if s.kind == .function { editFunction(si); return }
        if let a = s.extensionAnalysis {
            if a.usesFittingDialog {
                guard let nf = AnalysisDialogs.fittingCondition(s.peakFit, over: window) else { return }
                var ns = s
                ns.peakFit = nf
                guard let n2 = AnalysisDialogs.leastSquares(series: ns, over: window) else { return }
                doc.update(graph: gi, a.menuTitle) { $0.series[si] = n2 }
            }
            showResult(seriesIndex: si)
            return
        }
        guard let ns = AnalysisDialogs.leastSquares(series: s, over: window) else { return }
        doc.update(graph: gi, s.kind == .spline ? "スプライン補間" : "最小二乗") { $0.series[si] = ns }
        showResult(seriesIndex: si)
    }

    @objc func clearAnalysis(_ sender: Any?) {
        guard let doc, let si = chooseSeries("消去する最小二乗、スプラインの選択",
                                             where: { ($0.kind.hasCurve && $0.kind != .function) || $0.extensionAnalysis != nil }) else { return }
        doc.update(graph: gi, "Clear") {
            $0.series[si].kind = .normal
            $0.series[si].kindRaw = 0
            $0.series[si].extensionAnalysis = nil
        }
    }

    /// 任意関数描画
    @objc func drawFunction(_ sender: Any?) {
        guard let doc, let g = doc.activeGraph else { return }
        let functions = g.series.indices.filter { g.series[$0].kind == .function }
        var target: Int?
        if !functions.isEmpty {
            guard let k = ListDialogs.chooseOne(title: "結果代入するメモリーの選択", items: functions.map { g.series[$0].displayName },
                                                allowNew: true, over: window) else { return }
            if k >= 0 { target = functions[k] }
        }
        if let t = target { editFunction(t); return }
        guard let expr = ListDialogs.input(title: "描画関数の入力", prompt: "式:", text: "sin(x)", over: window),
              !expr.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do { _ = try Expression(expr) } catch {
            MessageBox.show("失敗しました\n\((error as? ExpressionError)?.message ?? "")", title: "Result", style: .warning); return
        }
        var name = "CALC.DAT"
        var k = 1
        while g.series.contains(where: { $0.name.uppercased() == name }) { k += 1; name = "CALC\(k).DAT" }
        var s = Series(name: name)
        s.kind = .function
        s.kindRaw = 3
        s.transformY = true
        s.expressionY = expr
        s.lineType = .solid
        s.dotType = 0
        let x = g.axes[0]
        s.curveStart = x.scaleType.isInverse ? 1 / x.from : x.from
        s.curveEnd = x.scaleType.isInverse ? 1 / x.to : x.to
        s.curveDivisions = 101
        if x.scaleType.isLog { s.curveSpacing = .exponential }
        guard let ns = AnalysisDialogs.leastSquares(series: s, over: window) else { return }
        doc.update(graph: gi, "任意関数描画") { $0.series.append(ns) }
    }

    func editFunction(_ si: Int) {
        guard let doc, let g = doc.activeGraph, si < g.series.count else { return }
        var s = g.series[si]
        guard let expr = ListDialogs.input(title: "描画関数の入力", prompt: "式:", text: s.expressionY, over: window) else { return }
        s.expressionY = expr
        guard let ns = AnalysisDialogs.leastSquares(series: s, over: window) else { return }
        doc.update(graph: gi, "任意関数描画") { $0.series[si] = ns }
    }

    @objc func showConstants(_ sender: Any?) {
        guard let doc, let g = doc.activeGraph else { return }
        let graphIndex = gi
        let apply: ([Double]) -> Void = { values in
            doc.update(graph: graphIndex, "定数設定") { $0.constants = values }
        }
        guard let values = AnalysisDialogs.constants(g.constants, over: window, apply: apply) else { return }
        apply(values)
    }

    /// Copy to Clipboard: 最小二乗・スプライン・任意関数の連続データ
    @objc func copyCurveData(_ sender: Any?) {
        guard let doc, let g = doc.activeGraph,
              let si = chooseSeries("クリップボードへコピーするデータの選択", where: { $0.kind.hasCurve || $0.extensionAnalysis != nil }) else { return }
        let d = doc.plotData()[gi][si]
        let pts: [(Double, Double)] = g.series[si].kind == .function ? Array(zip(d.x, d.y)) : d.curve.map { ($0.x, $0.y) }
        var out = d.resultLines.map { $0 + "\r\n" }.joined()
        for p in pts where p.0.isFinite && p.1.isFinite {
            out += String(format: "%+9e", p.0) + "\t" + String(format: "%+9e", p.1) + "\r\n"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(out, forType: .string)
        setStatus("連続データ \(pts.count) 点をクリップボードにコピーしました")
    }

    // MARK: - その他

    @objc func showCalculator(_ sender: Any?) { Calculator.run(over: window, constants: doc?.activeGraph?.constants ?? []) }

    /// 再描画(F2): データファイルを読み直して描き直す
    @objc func redraw(_ sender: Any?) {
        doc?.reloadChangedDataFiles(force: true)
        canvas.needsDisplay = true
    }

    // MARK: - マウスから

    func handleDoubleClick(_ hit: CanvasView.Hit) {
        switch hit {
        case .object(let g, let id), .arrowEnd(let g, let id, _):
            doc?.activeGraphIndex = g
            editObject(id)
        case .axis(let g, let axis):
            doc?.activeGraphIndex = g
            guard let graph = doc?.activeGraph else { return }
            if axis == 2 && !graph.uIndependent { showAxis(0) }
            else if axis == 3 && !graph.rIndependent { showAxis(1) }
            else { showAxis(axis) }
        case .frame(let g, _):
            doc?.activeGraphIndex = g
            showFrameDialog(nil)
        case .inside(let g):
            doc?.activeGraphIndex = g
            showDataManager(nil)
        case .none:
            break
        }
    }

    /// 右ボタンのメニュー
    func contextMenu(for hit: CanvasView.Hit) -> NSMenu {
        let m = NSMenu()
        func add(_ title: String, _ action: Selector, tag: Int = 0) {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
            i.tag = tag
            i.target = self
            m.addItem(i)
        }
        switch hit {
        case .object, .arrowEnd:
            add("前へ", #selector(bringForward(_:)))
            add("後ろへ", #selector(sendBackward(_:)))
            m.addItem(.separator())
            add("コピー", #selector(copyObject(_:)))
            add("カット", #selector(cutObject(_:)))
            add("削除", #selector(delete(_:)))
        default:
            add("データの設定…", #selector(showDataManager(_:)))
            m.addItem(.separator())
            add("X 軸…", #selector(showAxisDialog(_:)), tag: 0)
            add("Y 軸…", #selector(showAxisDialog(_:)), tag: 1)
            add("U 軸…", #selector(showAxisDialog(_:)), tag: 2)
            add("R 軸…", #selector(showAxisDialog(_:)), tag: 3)
            m.addItem(.separator())
            add("枠…", #selector(showFrameDialog(_:)))
            m.addItem(.separator())
            add("文字を入れる", #selector(insertOtherText(_:)))
            add("矢印を入れる", #selector(insertArrow(_:)))
            add("枠を入れる", #selector(insertBox(_:)))
        }
        return m
    }

    /// 右ボタンで囲んだ範囲のメニュー
    func showRegionMenu(pageRect r: CGRect, event: NSEvent, in view: NSView) {
        let m = NSMenu()
        let handler = RegionMenuHandler(controller: self, rect: r)
        for (title, tag) in [("この範囲をコピー", 0), ("この範囲を PDF で保存", 1)] {
            let i = NSMenuItem(title: title, action: #selector(RegionMenuHandler.run(_:)), keyEquivalent: "")
            i.target = handler; i.tag = tag; m.addItem(i)
        }
        m.addItem(.separator())
        for (title, tag) in [("この範囲に拡大", 2), ("この範囲をマスク", 3)] {
            let i = NSMenuItem(title: title, action: #selector(RegionMenuHandler.run(_:)), keyEquivalent: "")
            i.target = handler; i.tag = tag; m.addItem(i)
        }
        objc_setAssociatedObject(m, &RegionMenuHandler.key, handler, .OBJC_ASSOCIATION_RETAIN)
        NSMenu.popUpContextMenu(m, with: event, for: view)
    }

    func regionAction(_ tag: Int, rect r: CGRect) {
        guard let doc else { return }
        switch tag {
        case 0: putFigureOnPasteboard(renderer: doc.renderer(), rect: r)
        case 1:
            let panel = NSSavePanel()
            panel.nameFieldStringValue = exportBaseName() + ".pdf"
            panel.allowedContentTypes = [.pdf]
            if panel.runModal() == .OK, let url = panel.url {
                try? GraphExporter.pdfData(renderer: doc.renderer(), rect: r).write(to: url)
            }
        case 2: applyTrimming(pageRect: r)
        case 3: applyDataMask(pageRect: r)
        default: break
        }
    }
}

/// 右ボタンで囲んだ範囲のメニューの受け手
@MainActor
final class RegionMenuHandler: NSObject {
    nonisolated(unsafe) static var key: UInt8 = 0
    weak var controller: GraphWindowController?
    let rect: CGRect

    init(controller: GraphWindowController, rect: CGRect) {
        self.controller = controller
        self.rect = rect
    }

    @objc func run(_ sender: NSMenuItem) { controller?.regionAction(sender.tag, rect: rect) }
}

/// グラフの保存の窓の下に付けるもの(「SMP にデータも入れる」「16 ビット版の形式で保存する」)
@MainActor
enum SaveAccessory {
    static func make() -> (NSView, () -> Bool) {
        let v = TemplateView(.saveOptions)
        v.setChecked(787, AppSettings.shared.saveDataWithGraph)
        v.setChecked(788, false)
        v.setEnabled(788, false)
        v.on(787) { AppSettings.shared.saveDataWithGraph = v.isChecked(787) }
        return (v, { v.isChecked(787) })
    }
}
