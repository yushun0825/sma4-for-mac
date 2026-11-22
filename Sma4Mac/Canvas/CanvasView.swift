import AppKit
import Sma4Core

/// 窓の中の白い作業面。グラフを描き、マウスでの移動・大きさの変更・ダブルクリックでの設定・右ボタンのメニューを受け付ける。
/// 表示の大きさ(%)は、100% で 1 mm が 96/25.4 点(96 dpi の画面での実寸)。
@MainActor
final class CanvasView: NSView {
    weak var document: Sma4Document?
    weak var controller: GraphWindowController?

    /// Windows の 100% 表示での 1 mm の長さ(点)
    static let pointsPerMM: CGFloat = 96.0 / 25.4

    /// 印刷イメージの表示(ファイル → Preview)
    var preview = false { didSet { updateSize(); needsDisplay = true } }

    /// 選んでいるオブジェクト(選択中のグラフの中)
    var selection: Set<UUID> = [] { didSet { needsDisplay = true; controller?.selectionDidChange() } }

    enum Mode: Equatable { case normal, trimming, readValue, dataMask, placeText, placeShape, placeDot, pickGraph }
    var mode: Mode = .normal {
        didSet {
            dragRect = nil
            if oldValue == .readValue && mode != .readValue { readValue = nil }
            needsDisplay = true
            window?.invalidateCursorRects(for: self)
            controller?.modeDidChange()
        }
    }

    // 置く途中のもの(ダイアログの「貼付」「マウスで位置設定」のあと)
    var placingText: TextObject?
    var placingShape: ShapeObject?
    var placingDot: DotObject?
    var onPlaced: ((CGPoint, CGPoint) -> Void)?
    private var ghostPoint: CGPoint?

    private enum Drag {
        case objects(graph: Int, ids: Set<UUID>, original: SMPProject, start: CGPoint)
        case arrowEnd(graph: Int, id: UUID, end: Int, original: SMPProject)
        case frame(graph: Int, edges: Edges, original: SMPProject, start: CGPoint)
        case rect(start: CGPoint)
        case place(start: CGPoint)
    }
    private var drag: Drag?
    private(set) var dragRect: CGRect?
    private var placeLine: (CGPoint, CGPoint)?
    private var rightDragStart: CGPoint?
    private var didDrag = false

    struct Edges: OptionSet {
        let rawValue: Int
        static let left = Edges(rawValue: 1), right = Edges(rawValue: 2), top = Edges(rawValue: 4), bottom = Edges(rawValue: 8)
        static let move = Edges(rawValue: 16)
    }

    // Read Value
    struct ReadValue: Equatable { var graph: Int; var series: Int; var index: Int; var x: Double; var y: Double }
    var readValue: ReadValue? { didSet { needsDisplay = true } }
    var readMark: ReadValue? { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }

    // MARK: - 座標

    /// 0.01 mm あたりの点の数と、用紙の左上の位置
    var metrics: (unit: CGFloat, origin: CGPoint) {
        if preview {
            let paper = pageSize
            let avail = enclosingScrollView?.contentSize ?? bounds.size
            let k = max(min((avail.width - 40) / paper.width, (avail.height - 40) / paper.height), 0.0005)
            let o = CGPoint(x: (avail.width - paper.width * k) / 2, y: (avail.height - paper.height * k) / 2)
            return (k, o)
        }
        let size = AppSettings.shared.screenSize > 0 ? AppSettings.shared.screenSize : 70
        return (CanvasView.pointsPerMM * CGFloat(size) / 100 / 100, CGPoint(x: 0, y: 0))
    }

    var unit: CGFloat { metrics.unit }

    var pageSize: CGSize {
        let g = document?.project.graphs.first
        let s = (g?.page ?? PageSetup()).paperSizeMM
        let scale = Double(document?.project.graphs.first?.page.tail.first ?? 100) / 100
        let k = scale > 0 ? 1 / scale : 1
        return CGSize(width: s.width * 100 * k, height: s.height * 100 * k)
    }

    func viewPoint(_ p: CGPoint) -> CGPoint {
        let m = metrics
        return CGPoint(x: m.origin.x + p.x * m.unit, y: m.origin.y + p.y * m.unit)
    }

    func pagePoint(_ v: CGPoint) -> CGPoint {
        let m = metrics
        return CGPoint(x: (v.x - m.origin.x) / m.unit, y: (v.y - m.origin.y) / m.unit)
    }

    func viewRect(_ r: CGRect) -> CGRect {
        let a = viewPoint(r.origin)
        return CGRect(x: a.x, y: a.y, width: r.width * unit, height: r.height * unit)
    }

    func updateSize() {
        let avail = enclosingScrollView?.contentSize ?? bounds.size
        if preview {
            setFrameSize(avail)
            return
        }
        var content = CGRect(origin: .zero, size: pageSize)
        if let doc = document {
            for g in doc.project.graphs {
                content = content.union(frameRectOnPage(g).insetBy(dx: -4000, dy: -4000))
            }
        }
        let u = unit
        setFrameSize(NSSize(width: max(content.maxX * u, avail.width), height: max(content.maxY * u, avail.height)))
    }

    // MARK: - 描画

    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext, let doc = document else { return }
        let settings = AppSettings.shared
        if preview {
            NSColor(calibratedWhite: 0.5, alpha: 1).setFill()
            dirtyRect.fill()
            let paper = viewRect(CGRect(origin: .zero, size: pageSize))
            ctx.saveGState()
            ctx.setShadow(offset: CGSize(width: 3, height: 3), blur: 0, color: NSColor.black.withAlphaComponent(0.6).cgColor)
            NSColor.white.setFill()
            ctx.fill(paper)
            ctx.restoreGState()
            NSColor.black.setStroke()
            NSBezierPath(rect: paper.insetBy(dx: -0.5, dy: -0.5)).stroke()
        } else {
            settings.backgroundColor.nsColor.setFill()
            dirtyRect.fill()
            if settings.gridMM > 0 { drawGrid(ctx, dirty: dirtyRect, stepMM: settings.gridMM, color: settings.gridColor) }
        }

        let renderer = doc.renderer()
        let m = metrics
        ctx.saveGState()
        if preview { ctx.clip(to: viewRect(CGRect(origin: .zero, size: pageSize))) }
        ctx.translateBy(x: m.origin.x, y: m.origin.y)
        ctx.scaleBy(x: m.unit, y: m.unit)
        renderer.draw(in: ctx)
        ctx.restoreGState()

        drawOverlay(ctx, renderer: renderer)
    }

    /// グリッド表示(格子点に点を打つ)
    func drawGrid(_ ctx: CGContext, dirty: NSRect, stepMM: Double, color: SMPColor) {
        let step = CGFloat(stepMM) * 100 * unit
        guard step >= 3 else { return }
        ctx.saveGState()
        ctx.setFillColor(color.cgColor)
        let o = metrics.origin
        var x = o.x + (floor((dirty.minX - o.x) / step)) * step
        while x <= dirty.maxX {
            var y = o.y + (floor((dirty.minY - o.y) / step)) * step
            while y <= dirty.maxY {
                ctx.fill(CGRect(x: round(x), y: round(y), width: 1, height: 1))
                y += step
            }
            x += step
        }
        ctx.restoreGState()
    }

    func frameRectOnPage(_ g: Graph) -> CGRect {
        CGRect(x: 0, y: 0, width: g.width, height: g.height).applying(GraphRenderer.graphTransform(g))
    }

    func drawOverlay(_ ctx: CGContext, renderer: GraphRenderer) {
        guard let doc = document else { return }
        ctx.saveGState()
        ctx.setShouldAntialias(false)
        // 選択中のグラフ(グラフが 2 枚以上のとき): 枠の四隅と辺の中ほどに黒い四角
        if doc.project.graphs.count > 1, let g = doc.activeGraph, doc.soloGraph == nil || doc.soloGraph == doc.activeGraphIndex {
            let r = viewRect(frameRectOnPage(g)).integral
            NSColor.black.setFill()
            for p in handlePoints(r) { ctx.fill(CGRect(x: p.x - 2, y: p.y - 2, width: 5, height: 5)) }
        }
        // 選んだオブジェクト: 点線の四角
        if let g = doc.activeGraph {
            let t = GraphRenderer.graphTransform(g)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineWidth(1)
            for item in g.objects where selection.contains(item.id) {
                if case .shape(let s) = item.object, s.objectType != 3,
                   let (a, b) = GraphRenderer.shapePoints(s, GraphRenderer.Frame(g)) {
                    for p in [a, b] {
                        let v = viewPoint(p.applying(t))
                        ctx.fill(CGRect(x: round(v.x) - 2, y: round(v.y) - 2, width: 5, height: 5))
                    }
                } else if let b = renderer.objectBounds(item.object, graphIndex: doc.activeGraphIndex) {
                    let r = viewRect(b.applying(t)).insetBy(dx: -2, dy: -2).integral.offsetBy(dx: 0.5, dy: 0.5)
                    ctx.setLineDash(phase: 0, lengths: [2, 2])
                    ctx.stroke(r)
                    ctx.setLineDash(phase: 0, lengths: [])
                }
            }
        }
        // ドラッグ中の四角(トリミング・Data Mask・選択領域)
        if let r = dragRect {
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineDash(phase: 0, lengths: [3, 3])
            ctx.stroke(viewRect(r).integral.offsetBy(dx: 0.5, dy: 0.5))
            ctx.setLineDash(phase: 0, lengths: [])
        }
        // 矢印・枠を置く途中
        if let (a, b) = placeLine {
            let va = viewPoint(a), vb = viewPoint(b)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineDash(phase: 0, lengths: [3, 3])
            if mode == .placeShape, let s = placingShape, s.objectType == 3 {
                ctx.stroke(CGRect(x: min(va.x, vb.x), y: min(va.y, vb.y), width: abs(vb.x - va.x), height: abs(vb.y - va.y)))
            } else {
                ctx.move(to: va); ctx.addLine(to: vb); ctx.strokePath()
            }
            ctx.setLineDash(phase: 0, lengths: [])
        }
        // 文字を置く途中: マウスのところに四角い枠(位置は文字の開始の左下)
        if mode == .placeText, let p = ghostPoint, let t = placingText, let g = doc.activeGraph {
            let env = renderer.environment(for: doc.activeGraphIndex)
            let lay = renderer.textLayout(t, env: env)
            let z = CGFloat(g.zoomFactor) * unit
            let b = lay.bounds
            let v = viewPoint(p)
            let r = CGRect(x: v.x + b.minX * z, y: v.y + b.minY * z, width: max(b.width * z, 20), height: max(b.height * z, 10))
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.setLineDash(phase: 0, lengths: [2, 2])
            ctx.stroke(r.integral.offsetBy(dx: 0.5, dy: 0.5))
            ctx.setLineDash(phase: 0, lengths: [])
        }
        ctx.setShouldAntialias(true)
        // Read Value: 点を通る縦と横の線(設定の Read Value Color)
        if let rv = readValue, rv.graph < doc.project.graphs.count, rv.series < doc.project.graphs[rv.graph].series.count {
            let g = doc.project.graphs[rv.graph]
            let s = g.series[rv.series]
            let fr = GraphRenderer.Frame(g)
            if let p = fr.point(rv.x, rv.y, h: g.horizontalAxisIndex(for: s), v: g.verticalAxisIndex(for: s)) {
                let v = viewPoint(p.applying(GraphRenderer.graphTransform(g)))
                let box = viewRect(frameRectOnPage(g))
                ctx.setStrokeColor(AppSettings.shared.readValueColor.cgColor)
                ctx.setLineWidth(1)
                ctx.move(to: CGPoint(x: box.minX, y: round(v.y) + 0.5)); ctx.addLine(to: CGPoint(x: box.maxX, y: round(v.y) + 0.5))
                ctx.move(to: CGPoint(x: round(v.x) + 0.5, y: box.minY)); ctx.addLine(to: CGPoint(x: round(v.x) + 0.5, y: box.maxY))
                ctx.strokePath()
            }
            if let mk = readMark, mk.graph == rv.graph, mk.series == rv.series,
               let p = fr.point(mk.x, mk.y, h: g.horizontalAxisIndex(for: s), v: g.verticalAxisIndex(for: s)) {
                let v = viewPoint(p.applying(GraphRenderer.graphTransform(g)))
                ctx.setStrokeColor(AppSettings.shared.readValueColor.cgColor)
                ctx.setLineDash(phase: 0, lengths: [2, 2])
                let box = viewRect(frameRectOnPage(g))
                ctx.move(to: CGPoint(x: round(v.x) + 0.5, y: box.minY)); ctx.addLine(to: CGPoint(x: round(v.x) + 0.5, y: box.maxY))
                ctx.strokePath()
                ctx.setLineDash(phase: 0, lengths: [])
            }
        }
        ctx.restoreGState()
    }

    func handlePoints(_ r: CGRect) -> [CGPoint] {
        [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.midX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
         CGPoint(x: r.minX, y: r.midY), CGPoint(x: r.maxX, y: r.midY),
         CGPoint(x: r.minX, y: r.maxY), CGPoint(x: r.midX, y: r.maxY), CGPoint(x: r.maxX, y: r.maxY)]
    }

    // MARK: - 当たり判定

    enum Hit {
        case object(graph: Int, id: UUID)
        case arrowEnd(graph: Int, id: UUID, end: Int)
        case frame(graph: Int, edges: Edges)
        case axis(graph: Int, axis: Int)
        case inside(graph: Int)
        case none
    }

    var tolerance: CGFloat { 4 / unit }

    func hitTest(page p: CGPoint) -> Hit {
        guard let doc = document else { return .none }
        let renderer = doc.renderer()
        let order = graphOrder()
        for gi in order {
            let g = doc.project.graphs[gi]
            let t = GraphRenderer.graphTransform(g)
            let local = p.applying(t.inverted())
            let fr = GraphRenderer.Frame(g)
            let tol = tolerance / g.zoomFactor
            for item in g.objects.reversed() {
                switch item.object {
                case .shape(let s) where s.objectType != 3:
                    guard let (a, b) = GraphRenderer.shapePoints(s, fr) else { continue }
                    // 端をつかむと片方の端だけ、真ん中をつかむと全体が動く
                    if hypot(local.x - a.x, local.y - a.y) <= tol * 1.5 { return .arrowEnd(graph: gi, id: item.id, end: 0) }
                    if hypot(local.x - b.x, local.y - b.y) <= tol * 1.5 { return .arrowEnd(graph: gi, id: item.id, end: 1) }
                    if distance(local, a, b) <= tol + CGFloat(s.width) { return .object(graph: gi, id: item.id) }
                case .shape(let s):
                    guard let (a, b) = GraphRenderer.shapePoints(s, fr) else { continue }
                    let r = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
                    if r.insetBy(dx: -tol, dy: -tol).contains(local) && !r.insetBy(dx: tol, dy: tol).contains(local) {
                        return .object(graph: gi, id: item.id)
                    }
                default:
                    if let b = renderer.objectBounds(item.object, graphIndex: gi), b.insetBy(dx: -tol, dy: -tol).contains(local) {
                        return .object(graph: gi, id: item.id)
                    }
                }
            }
        }
        for gi in order {
            let g = doc.project.graphs[gi]
            let r = frameRectOnPage(g)
            let tol = tolerance
            let nearL = abs(p.x - r.minX) <= tol, nearR = abs(p.x - r.maxX) <= tol
            let nearT = abs(p.y - r.minY) <= tol, nearB = abs(p.y - r.maxY) <= tol
            let inX = p.x >= r.minX - tol && p.x <= r.maxX + tol
            let inY = p.y >= r.minY - tol && p.y <= r.maxY + tol
            var e: Edges = []
            if nearL && inY { e.insert(.left) }
            if nearR && inY { e.insert(.right) }
            if nearB && inX { e.insert(.bottom) }
            if nearT && inX {
                // U 軸(上の辺)をつかむとグラフ全体が動く。角は大きさの変更
                if e.isEmpty { return .frame(graph: gi, edges: .move) }
                e.insert(.top)
            }
            if !e.isEmpty { return .frame(graph: gi, edges: e) }
        }
        for gi in order {
            let g = doc.project.graphs[gi]
            let r = frameRectOnPage(g)
            if r.contains(p) { return .inside(graph: gi) }
            let band = 1500.0 * g.zoomFactor
            if p.x >= r.minX && p.x <= r.maxX {
                if p.y > r.maxY && p.y < r.maxY + band { return .axis(graph: gi, axis: 0) }
                if p.y < r.minY && p.y > r.minY - band { return .axis(graph: gi, axis: 2) }
            }
            if p.y >= r.minY && p.y <= r.maxY {
                if p.x < r.minX && p.x > r.minX - band * 1.5 { return .axis(graph: gi, axis: 1) }
                if p.x > r.maxX && p.x < r.maxX + band * 1.5 { return .axis(graph: gi, axis: 3) }
            }
        }
        return .none
    }

    func graphOrder() -> [Int] {
        guard let doc = document else { return [] }
        var all = Array(doc.project.graphs.indices)
        if let solo = doc.soloGraph { all = all.filter { $0 == solo } }
        if let i = all.firstIndex(of: doc.activeGraphIndex) { all.remove(at: i); all.insert(doc.activeGraphIndex, at: 0) }
        return all
    }

    /// その位置にあるグラフ(右クリックでグラフを選ぶため)
    func graphIndex(at p: CGPoint) -> Int? {
        guard let doc = document else { return nil }
        for gi in graphOrder() {
            let r = frameRectOnPage(doc.project.graphs[gi]).insetBy(dx: -1500, dy: -1500)
            if r.contains(p) { return gi }
        }
        return nil
    }

    func distance(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let l2 = dx * dx + dy * dy
        guard l2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / l2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }

    // MARK: - マウス

    func snapped(_ v: CGFloat) -> CGFloat {
        let s = CGFloat(AppSettings.shared.snapMM) * 100
        guard s > 0 else { return v.rounded() }
        return (v / s).rounded() * s
    }

    func snappedPoint(_ p: CGPoint) -> CGPoint { CGPoint(x: snapped(p.x), y: snapped(p.y)) }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        guard let doc = document else { return }
        let p = pagePoint(convert(event.locationInWindow, from: nil))
        didDrag = false

        switch mode {
        case .trimming, .dataMask:
            drag = .rect(start: p)
            dragRect = CGRect(origin: p, size: .zero)
            return
        case .placeShape:
            let s = snappedPoint(p)
            drag = .place(start: s)
            placeLine = (s, s)
            return
        case .placeText, .placeDot:
            let s = snappedPoint(p)
            mode = .normal
            onPlaced?(s, s)
            onPlaced = nil
            return
        case .pickGraph:
            if let gi = graphIndex(at: p) { doc.activeGraphIndex = gi }
            mode = .normal
            return
        case .readValue:
            updateReadValue(at: p)
            controller?.readValueChanged()
            return
        case .normal:
            break
        }

        let hit = hitTest(page: p)
        if event.clickCount >= 2 {
            controller?.handleDoubleClick(hit)
            return
        }
        switch hit {
        case .object(let gi, let id):
            if gi != doc.activeGraphIndex { doc.activeGraphIndex = gi; selection = [] }
            if event.modifierFlags.contains(.shift) {
                if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
            } else if !selection.contains(id) {
                selection = [id]
            }
            drag = .objects(graph: gi, ids: selection, original: doc.project, start: p)
        case .arrowEnd(let gi, let id, let end):
            if gi != doc.activeGraphIndex { doc.activeGraphIndex = gi }
            selection = [id]
            drag = .arrowEnd(graph: gi, id: id, end: end, original: doc.project)
        case .frame(let gi, let edges):
            doc.activeGraphIndex = gi
            selection = []
            drag = .frame(graph: gi, edges: edges, original: doc.project, start: p)
        case .inside(let gi), .axis(let gi, _):
            if gi != doc.activeGraphIndex { doc.activeGraphIndex = gi }
            selection = []
            drag = nil
        case .none:
            selection = []
            drag = nil
        }
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard let doc = document, let d = drag else { return }
        let p = pagePoint(convert(event.locationInWindow, from: nil))
        didDrag = true
        autoscroll(with: event)
        switch d {
        case .rect(let start):
            dragRect = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
            controller?.trimmingRectChanged(dragRect)
        case .place(let start):
            placeLine = (start, snappedPoint(p))
        case .objects(let gi, let ids, let original, let start):
            let g0 = original.graphs[gi]
            let z = g0.zoomFactor
            let dx = (p.x - start.x) / z, dy = (p.y - start.y) / z
            doc.preview { proj in
                proj = original
                for (k, item) in proj.graphs[gi].objects.enumerated() where ids.contains(item.id) {
                    proj.graphs[gi].objects[k].object = moved(item.object, dx: dx, dy: dy, graph: g0)
                }
            }
            controller?.showSelectionStatus()
        case .arrowEnd(let gi, let id, let end, let original):
            let g0 = original.graphs[gi]
            let local = p.applying(GraphRenderer.graphTransform(g0).inverted())
            doc.preview { proj in
                proj = original
                guard let k = proj.graphs[gi].objects.firstIndex(where: { $0.id == id }),
                      case .shape(var s) = proj.graphs[gi].objects[k].object else { return }
                setShapeEnd(&s, end: end, local: CGPoint(x: snapped(local.x), y: snapped(local.y)), graph: g0)
                proj.graphs[gi].objects[k].object = .shape(s)
            }
            controller?.showSelectionStatus()
        case .frame(let gi, let edges, let original, let start):
            let g0 = original.graphs[gi]
            let dx = p.x - start.x, dy = p.y - start.y
            doc.preview { proj in
                proj = original
                var g = g0
                let z = g0.zoomFactor
                if edges.contains(.move) {
                    g.left = Int(snapped(CGFloat(g0.left) + dx)); g.top = Int(snapped(CGFloat(g0.top) + dy))
                } else {
                    var l = CGFloat(g0.left), t = CGFloat(g0.top)
                    var w = CGFloat(g0.width), h = CGFloat(g0.height)
                    if edges.contains(.left) { let nl = snapped(l + dx); w -= (nl - l) / z; l = nl }
                    if edges.contains(.right) { w = snapped(w * z + dx) / z }
                    if edges.contains(.top) { let nt = snapped(t + dy); h -= (nt - t) / z; t = nt }
                    if edges.contains(.bottom) { h = snapped(h * z + dy) / z }
                    g.left = Int(l); g.top = Int(t)
                    g.width = Int(max(w, 500)); g.height = Int(max(h, 500))
                }
                proj.graphs[gi] = g
            }
            controller?.showGraphStatus()
        }
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard let doc = document, let d = drag else { return }
        drag = nil
        switch d {
        case .rect:
            let r = dragRect
            dragRect = nil
            let m = mode
            mode = .normal
            if let r, r.width > 30, r.height > 30 {
                if m == .trimming { controller?.applyTrimming(pageRect: r) }
                else if m == .dataMask { controller?.applyDataMask(pageRect: r) }
            }
        case .place(let start):
            let end = placeLine?.1 ?? start
            placeLine = nil
            mode = .normal
            onPlaced?(start, end)
            onPlaced = nil
        case .objects(_, _, let original, _):
            if didDrag { doc.commitPreview(from: original, actionName: "移動") }
        case .arrowEnd(_, _, _, let original):
            if didDrag { doc.commitPreview(from: original, actionName: "矢印の変更") }
        case .frame(_, let edges, let original, _):
            if didDrag { doc.commitPreview(from: original, actionName: edges.contains(.move) ? "グラフの移動" : "グラフの大きさ") }
        }
        needsDisplay = true
    }

    override func rightMouseDown(with event: NSEvent) {
        rightDragStart = pagePoint(convert(event.locationInWindow, from: nil))
        dragRect = nil
    }

    override func rightMouseDragged(with event: NSEvent) {
        guard let s = rightDragStart else { return }
        let p = pagePoint(convert(event.locationInWindow, from: nil))
        dragRect = CGRect(x: min(s.x, p.x), y: min(s.y, p.y), width: abs(p.x - s.x), height: abs(p.y - s.y))
        needsDisplay = true
    }

    override func rightMouseUp(with event: NSEvent) {
        defer { rightDragStart = nil }
        if let r = dragRect, r.width > 100, r.height > 100 {
            // 右ボタンで囲んだ範囲: 選択領域をCopy・メタファイル形式で保存・トリミング・Data Mask
            needsDisplay = true
            controller?.showRegionMenu(pageRect: r, event: event, in: self)
            dragRect = nil
            needsDisplay = true
            return
        }
        dragRect = nil
        let p = pagePoint(convert(event.locationInWindow, from: nil))
        let hit = hitTest(page: p)
        switch hit {
        case .object(let gi, let id), .arrowEnd(let gi, let id, _):
            document?.activeGraphIndex = gi
            if !selection.contains(id) { selection = [id] }
        default:
            // 右ボタンでシートの上のグラフを選ぶ
            if let gi = graphIndex(at: p) { document?.activeGraphIndex = gi }
            selection = []
        }
        if let menu = controller?.contextMenu(for: hit) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    override func mouseMoved(with event: NSEvent) {
        let p = pagePoint(convert(event.locationInWindow, from: nil))
        if mode == .readValue {
            updateReadValue(at: p)
            controller?.readValueChanged()
        }
        if mode == .placeText {
            ghostPoint = snappedPoint(p)
            needsDisplay = true
        }
        controller?.mouseMovedOnCanvas(page: p)
        updateCursor(page: p)
    }

    override func scrollWheel(with event: NSEvent) {
        // Read Value の時は、ホイールで点を動かす
        if mode == .readValue, let rv = readValue {
            let d = event.scrollingDeltaY
            if abs(d) >= 1 {
                stepReadValue(rv, by: d > 0 ? -1 : 1)
                return
            }
        }
        super.scrollWheel(with: event)
    }

    func updateCursor(page p: CGPoint) {
        switch mode {
        case .trimming, .dataMask, .placeShape, .placeDot, .readValue, .pickGraph: NSCursor.crosshair.set(); return
        case .placeText: NSCursor.arrow.set(); return
        case .normal: break
        }
        switch hitTest(page: p) {
        case .frame(_, let e):
            if e.contains(.move) { NSCursor.openHand.set() }
            else if (e.contains(.left) || e.contains(.right)) && !(e.contains(.top) || e.contains(.bottom)) { NSCursor.resizeLeftRight.set() }
            else if (e.contains(.top) || e.contains(.bottom)) && !(e.contains(.left) || e.contains(.right)) { NSCursor.resizeUpDown.set() }
            else { NSCursor.crosshair.set() }
        case .object, .arrowEnd: NSCursor.pointingHand.set()
        default: NSCursor.arrow.set()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .cursorUpdate], owner: self))
    }

    override func cursorUpdate(with event: NSEvent) {}

    // MARK: - オブジェクトの移動

    func moved(_ o: GraphObject, dx: CGFloat, dy: CGFloat, graph g: Graph) -> GraphObject {
        switch o {
        case .text(var t):
            let z = t.absolutePosition ? g.zoomFactor : 1
            t.x = Int(snapped(CGFloat(t.x) + dx * z))
            t.y = Int(snapped(CGFloat(t.y) + dy * z))
            return .text(t)
        case .dot(var d):
            d.x = Int(snapped(CGFloat(d.x) + dx)); d.y = Int(snapped(CGFloat(d.y) + dy))
            return .dot(d)
        case .shape(var s):
            let fr = GraphRenderer.Frame(g)
            guard let (a, b) = GraphRenderer.shapePoints(s, fr) else { return o }
            let na = CGPoint(x: snapped(a.x + dx), y: snapped(a.y + dy))
            let nb = CGPoint(x: na.x + (b.x - a.x), y: na.y + (b.y - a.y))
            setShapeEnd(&s, end: 0, local: na, graph: g)
            setShapeEnd(&s, end: 1, local: nb, graph: g)
            return .shape(s)
        case .picture(var pic):
            let z = pic.shape.absolutePosition ? g.zoomFactor : 1
            let w = pic.shape.x2 - pic.shape.x1, h = pic.shape.y2 - pic.shape.y1
            pic.shape.x1 = Double(snapped(CGFloat(pic.shape.x1 * 100) + dx * z)) / 100
            pic.shape.y1 = Double(snapped(CGFloat(pic.shape.y1 * 100) + dy * z)) / 100
            pic.shape.x2 = pic.shape.x1 + w
            pic.shape.y2 = pic.shape.y1 + h
            return .picture(pic)
        case .raw:
            return o
        }
    }

    /// 矢印などの端をグラフの中の位置に合わせる(位置の単位が軸の値なら値に直す)
    func setShapeEnd(_ s: inout ShapeObject, end: Int, local p: CGPoint, graph g: Graph) {
        let fr = GraphRenderer.Frame(g)
        // 絶対位置なら mm の値は用紙の左上から
        let z = Double(g.zoomFactor)
        func vx(_ x: CGFloat) -> Double {
            switch s.xReference {
            case 1: return fr.scales[0].value(atFraction: Double(x) / fr.width)
            case 2: return fr.scales[2].value(atFraction: Double(x) / fr.width)
            default: return s.absolutePosition ? (Double(x) * z + Double(g.left)) / 100 : Double(x) / 100
            }
        }
        func vy(_ y: CGFloat) -> Double {
            switch s.yReference {
            case 1: return fr.scales[1].value(atFraction: 1 - Double(y) / fr.height)
            case 2: return fr.scales[3].value(atFraction: 1 - Double(y) / fr.height)
            default: return s.absolutePosition ? (Double(y) * z + Double(g.top)) / 100 : Double(y) / 100
            }
        }
        if end == 0 { s.x1 = vx(p.x); s.y1 = vy(p.y) } else { s.x2 = vx(p.x); s.y2 = vy(p.y) }
    }

    // MARK: - キー

    override func keyDown(with event: NSEvent) {
        guard let doc = document else { return }
        if event.keyCode == 53 { // esc
            if mode != .normal {
                onPlaced = nil
                placeLine = nil
                mode = .normal
            } else if preview {
                controller?.togglePreview(nil)
            } else {
                selection = []
            }
            return
        }
        if event.keyCode == 120 { // F2: 描き直す
            controller?.redraw(nil)
            return
        }
        if mode == .readValue, let rv = readValue, event.keyCode == 123 || event.keyCode == 124 {
            stepReadValue(rv, by: event.keyCode == 123 ? -1 : 1)
            return
        }
        let step: CGFloat = event.modifierFlags.contains(.option) ? 10 : CGFloat(max(AppSettings.shared.snapMM, 0.1)) * 100
        var dx: CGFloat = 0, dy: CGFloat = 0
        switch event.keyCode {
        case 51, 117: controller?.delete(nil); return
        case 123: dx = -step
        case 124: dx = step
        case 125: dy = step
        case 126: dy = -step
        default: super.keyDown(with: event); return
        }
        guard !selection.isEmpty, let g = doc.activeGraph else { return }
        let ids = selection
        doc.update(graph: doc.activeGraphIndex, "移動") { graph in
            for (k, item) in graph.objects.enumerated() where ids.contains(item.id) {
                graph.objects[k].object = self.movedExact(item.object, dx: dx / g.zoomFactor, dy: dy / g.zoomFactor, graph: g)
            }
        }
    }

    func movedExact(_ o: GraphObject, dx: CGFloat, dy: CGFloat, graph g: Graph) -> GraphObject {
        switch o {
        case .text(var t): t.x += Int(dx); t.y += Int(dy); return .text(t)
        case .dot(var d): d.x += Int(dx); d.y += Int(dy); return .dot(d)
        case .shape(var s):
            let fr = GraphRenderer.Frame(g)
            guard let (a, b) = GraphRenderer.shapePoints(s, fr) else { return o }
            setShapeEnd(&s, end: 0, local: CGPoint(x: a.x + dx, y: a.y + dy), graph: g)
            setShapeEnd(&s, end: 1, local: CGPoint(x: b.x + dx, y: b.y + dy), graph: g)
            return .shape(s)
        case .picture(var pic):
            let z = pic.shape.absolutePosition ? Double(g.zoomFactor) : 1
            pic.shape.x1 += Double(dx) * z / 100; pic.shape.x2 += Double(dx) * z / 100
            pic.shape.y1 += Double(dy) * z / 100; pic.shape.y2 += Double(dy) * z / 100
            return .picture(pic)
        case .raw: return o
        }
    }

    // MARK: - Read Value

    func updateReadValue(at p: CGPoint) {
        guard let doc = document, let g = doc.activeGraph else { readValue = nil; return }
        let gi = doc.activeGraphIndex
        let data = doc.plotData()
        guard gi < data.count else { return }
        let local = p.applying(GraphRenderer.graphTransform(g).inverted())
        let fr = GraphRenderer.Frame(g)
        var best: (ReadValue, CGFloat)?
        let only = controller?.readValueSeries
        for (si, s) in g.series.enumerated() where s.visible && si < data[gi].count {
            if let only, only != si { continue }
            let d = data[gi][si]
            let h = g.horizontalAxisIndex(for: s), v = g.verticalAxisIndex(for: s)
            for i in 0..<min(d.x.count, d.y.count) {
                guard d.x[i].isFinite, d.y[i].isFinite, let q = fr.point(d.x[i], d.y[i], h: h, v: v) else { continue }
                let dist = abs(q.x - local.x) + abs(q.y - local.y) * 0.2
                if best == nil || dist < best!.1 {
                    best = (ReadValue(graph: gi, series: si, index: i, x: d.x[i], y: d.y[i]), dist)
                }
            }
        }
        if let b = best?.0 { readValue = b }
    }

    func stepReadValue(_ rv: ReadValue, by delta: Int) {
        guard let doc = document else { return }
        let data = doc.plotData()
        guard rv.graph < data.count, rv.series < data[rv.graph].count else { return }
        let d = data[rv.graph][rv.series]
        let n = min(d.x.count, d.y.count)
        guard n > 0 else { return }
        var i = max(0, min(n - 1, rv.index + delta))
        // 欠損の点は飛ばす
        while i > 0 && i < n - 1 && !(d.x[i].isFinite && d.y[i].isFinite) { i += delta > 0 ? 1 : -1 }
        readValue = ReadValue(graph: rv.graph, series: rv.series, index: i, x: d.x[i], y: d.y[i])
        controller?.readValueChanged()
    }

    func setReadValue(series si: Int, index i: Int) {
        guard let doc = document else { return }
        let gi = doc.activeGraphIndex
        let data = doc.plotData()
        guard gi < data.count, si < data[gi].count else { return }
        let d = data[gi][si]
        guard i >= 0, i < min(d.x.count, d.y.count) else { return }
        readValue = ReadValue(graph: gi, series: si, index: i, x: d.x[i], y: d.y[i])
    }
}
