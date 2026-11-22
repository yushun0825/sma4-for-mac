import AppKit
import Sma4Core

/// 主窓。上からツールバー・白い作業面・ステータスバー。
@MainActor
final class GraphWindowController: NSWindowController, NSWindowDelegate, NSMenuItemValidation {
    let canvas = CanvasView(frame: NSRect(x: 0, y: 0, width: 800, height: 1000))
    let scrollView = NSScrollView()
    let toolbarStrip = ToolbarStrip(frame: NSRect(x: 0, y: 0, width: 900, height: ToolbarStrip.height))
    let statusBar = StatusBar(frame: NSRect(x: 0, y: 0, width: 900, height: StatusBar.height))
    private var toolbarHeight: NSLayoutConstraint!
    private var statusHeight: NSLayoutConstraint!
    /// Read Value で見る系列(nil なら全部から近い点)
    var readValueSeries: Int?
    var readValuePanel: ReadValuePanel?
    private var hint: String?

    var doc: Sma4Document? { document as? Sma4Document }

    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 620),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable],
                              backing: .buffered, defer: false)
        window.minSize = NSSize(width: 480, height: 320)
        window.tabbingMode = .disallowed
        super.init(window: window)
        window.delegate = self
        setupContent()
        window.setFrameAutosaveName("Sma4MainWindow")
    }

    required init?(coder: NSCoder) { fatalError() }

    override var document: AnyObject? {
        didSet {
            canvas.document = doc
            canvas.controller = self
            canvas.updateSize()
            canvas.needsDisplay = true
            NotificationCenter.default.removeObserver(self)
            if let d = doc {
                NotificationCenter.default.addObserver(self, selector: #selector(projectChanged(_:)), name: Sma4Document.projectChanged, object: d)
                NotificationCenter.default.addObserver(self, selector: #selector(projectChanged(_:)), name: Sma4Document.selectionChanged, object: d)
            }
            NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged(_:)), name: AppSettings.settingsChanged, object: nil)
            NotificationCenter.default.addObserver(self, selector: #selector(boundsChanged(_:)), name: NSView.frameDidChangeNotification, object: scrollView.contentView)
            DispatchQueue.main.async { [weak self] in
                self?.canvas.updateSize()
                self?.checkMissingData()
            }
            refreshStatus()
            validateToolbar()
        }
    }

    override func windowTitle(forDocumentDisplayName displayName: String) -> String {
        "Sma4 for Mac - " + (doc?.fileURL == nil && doc?.suggestedBaseName == nil ? "(Untitled)" : displayName)
    }

    func setupContent() {
        guard let window else { return }
        let container = NSView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = AppSettings.shared.backgroundColor.nsColor
        scrollView.documentView = canvas
        scrollView.contentView.postsFrameChangedNotifications = true
        for v in [toolbarStrip, scrollView, statusBar] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(v)
        }
        toolbarHeight = toolbarStrip.heightAnchor.constraint(equalToConstant: ToolbarStrip.height)
        statusHeight = statusBar.heightAnchor.constraint(equalToConstant: StatusBar.height)
        NSLayoutConstraint.activate([
            toolbarStrip.topAnchor.constraint(equalTo: container.topAnchor),
            toolbarStrip.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            toolbarStrip.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            toolbarHeight,
            scrollView.topAnchor.constraint(equalTo: toolbarStrip.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            statusHeight,
        ])
        toolbarStrip.onHint = { [weak self] h in
            self?.hint = h
            self?.refreshStatus()
        }
        window.contentView = container
        window.makeFirstResponder(canvas)
        applyBarVisibility()
    }

    func applyBarVisibility() {
        let s = AppSettings.shared
        toolbarStrip.isHidden = !s.showToolbar
        toolbarHeight.constant = s.showToolbar ? ToolbarStrip.height : 0
        statusBar.isHidden = !s.showStatusBar
        statusHeight.constant = s.showStatusBar ? StatusBar.height : 0
    }

    @objc func projectChanged(_ note: Notification) {
        canvas.updateSize()
        canvas.needsDisplay = true
        if let g = doc?.activeGraph {
            let ids = Set(g.objects.map(\.id))
            if !canvas.selection.isSubset(of: ids) { canvas.selection = canvas.selection.intersection(ids) }
        } else if !canvas.selection.isEmpty {
            canvas.selection = []
        }
        synchronizeWindowTitleWithDocumentName()
        refreshStatus()
        validateToolbar()
        readValuePanel?.refresh()
    }

    @objc func settingsChanged(_ note: Notification) {
        applyBarVisibility()
        scrollView.backgroundColor = AppSettings.shared.backgroundColor.nsColor
        canvas.updateSize()
        canvas.needsDisplay = true
    }

    @objc func boundsChanged(_ note: Notification) {
        if canvas.preview { canvas.updateSize() }
        canvas.updateSize()
    }

    func validateToolbar() { toolbarStrip.validate(with: self) }

    func selectionDidChange() {
        validateToolbar()
        showSelectionStatus()
    }

    func modeDidChange() {
        validateToolbar()
        refreshStatus()
        if canvas.mode != .readValue, let p = readValuePanel {
            p.close()
            readValuePanel = nil
        }
    }

    // MARK: - ステータスバー

    private var lastMessage = ""

    func setStatus(_ s: String) {
        lastMessage = s
        refreshStatus()
    }

    func refreshStatus() {
        statusBar.text = hint ?? lastMessage
        if let doc, doc.project.graphs.count > 1, let g = doc.activeGraph {
            statusBar.right.stringValue = "Graph: \(doc.activeGraphIndex + 1)/\(doc.project.graphs.count)  \(g.name)"
        } else {
            statusBar.right.stringValue = canvas.preview ? "Preview" : ""
        }
    }

    func mouseMovedOnCanvas(page p: CGPoint) {
        guard let doc else { return }
        switch canvas.mode {
        case .readValue, .trimming, .dataMask: break
        default:
            if !canvas.selection.isEmpty { return }
        }
        guard let g = doc.activeGraph else { return }
        let local = p.applying(GraphRenderer.graphTransform(g).inverted())
        let fr = GraphRenderer.Frame(g)
        if fr.rect.insetBy(dx: -1, dy: -1).contains(local) {
            let x = fr.scales[0].value(atFraction: Double(local.x) / fr.width)
            let y = fr.scales[1].value(atFraction: 1 - Double(local.y) / fr.height)
            if canvas.mode == .normal || canvas.mode == .trimming || canvas.mode == .dataMask {
                setStatus(String(format: "座標 (%6.4e, %6.4e)", x, y))
            }
        } else if canvas.mode == .normal {
            setStatus(String(format: "(%3d,%3d)", Int(p.x / 100), Int(p.y / 100)))
        }
    }

    /// トリミング・Data Mask のドラッグ中の範囲
    func trimmingRectChanged(_ r: CGRect?) {
        guard let r, let g = doc?.activeGraph else { return }
        let t = GraphRenderer.graphTransform(g).inverted()
        let a = CGPoint(x: r.minX, y: r.minY).applying(t), b = CGPoint(x: r.maxX, y: r.maxY).applying(t)
        let fr = GraphRenderer.Frame(g)
        let x0 = fr.scales[0].value(atFraction: Double(a.x) / fr.width), x1 = fr.scales[0].value(atFraction: Double(b.x) / fr.width)
        let y0 = fr.scales[1].value(atFraction: 1 - Double(b.y) / fr.height), y1 = fr.scales[1].value(atFraction: 1 - Double(a.y) / fr.height)
        setStatus(String(format: "T: (%4.2e, %4.2e)", x0, y0) + String(format: "-(%4.2e, %4.2e)", x1, y1))
    }

    /// 選んだものの位置(「選択: title: …」の形)
    func showSelectionStatus() {
        guard let doc, let g = doc.activeGraph, let id = canvas.selection.first,
              let item = g.objects.first(where: { $0.id == id }) else { return }
        var s = "選択: "
        switch item.object {
        case .text(let t):
            s += "title: " + String(format: "(%5.1lf,%5.1lf) %@", Double(t.x) / 100, Double(t.y) / 100, RichTextParser.plainText(t.text))
        case .dot(let d):
            s += "point: " + String(format: "(%5.1lf,%5.1lf)", Double(d.x) / 100, Double(d.y) / 100)
        case .shape(let sh) where sh.isBox:
            s += "枠: " + String(format: "(%5.1lf,%5.1lf)-(%5.1lf,%5.1lf)", sh.x1, sh.y1, sh.x2, sh.y2)
        case .shape(let sh):
            s += "arrow: " + String(format: "(%5.2f, %5.2f) -( %5.2f, %5.2f)", sh.x1, sh.y1, sh.x2, sh.y2)
        case .picture(let p):
            s += "図: " + String(format: "(%5.1lf,%5.1lf)-(%5.1lf,%5.1lf)", p.shape.x1, p.shape.y1, p.shape.x2, p.shape.y2)
        case .raw:
            s += "?"
        }
        if canvas.selection.count > 1 { s += "  ほか \(canvas.selection.count - 1) 個" }
        setStatus(s)
    }

    func showGraphStatus() {
        guard let g = doc?.activeGraph else { return }
        setStatus("Graph: " + String(format: "(%5.1lf,%5.1lf) %5.1lf x %5.1lf", Double(g.left) / 100, Double(g.top) / 100,
                                     Double(g.width) * g.zoomFactor / 100, Double(g.height) * g.zoomFactor / 100))
    }

    // MARK: - Read Value

    func readValueChanged() {
        readValuePanel?.refresh()
        guard let doc, let rv = canvas.readValue, rv.graph < doc.project.graphs.count,
              rv.series < doc.project.graphs[rv.graph].series.count else { return }
        let s = doc.project.graphs[rv.graph].series[rv.series]
        setStatus("\(s.displayName) [\(rv.index + 1)]  X = \(Num.g(rv.x))  Y = \(Num.g(rv.y))")
    }

    // MARK: - ウインドウ

    func windowWillClose(_ notification: Notification) {
        readValuePanel?.close()
        readValuePanel = nil
        NotificationCenter.default.removeObserver(self)
    }

    func windowDidResize(_ notification: Notification) {
        canvas.updateSize()
        if canvas.preview { canvas.needsDisplay = true }
    }

    /// SMP にデータが埋め込まれておらず、元のファイルも見つからない系列
    func checkMissingData() {
        guard !SnapshotRunner.isActive, !SelfTestRunner.isActive, let doc else { return }
        let missing = doc.project.graphs.flatMap { g in
            g.series.filter { $0.kind != .function && doc.project.dataFile(named: $0.name) == nil }
        }
        guard !missing.isEmpty else { return }
        let dlg = Dialog(.missingFiles)
        dlg.page.list(561)?.items = missing.map { $0.path.isEmpty ? $0.name : $0.path }
        dlg.buttons[559] = { true }
        guard dlg.run(over: window) == 559 else { return }
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "データファイルのあるフォルダを選んでください。"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        var p = doc.project
        Sma4Document.loadMissingData(&p, baseURL: dir)
        let found = p.dataFiles.count - doc.project.dataFiles.count
        doc.update("データファイルの読み込み") { $0 = p }
        setStatus(found > 0 ? "\(found) 個のデータファイルを読み込みました" : "そのフォルダには見つかりませんでした")
    }
}
