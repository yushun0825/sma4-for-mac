import Foundation
import CoreGraphics

/// 拡張メタファイル(EMF)への書き出し。
/// 図をいったん PDF に描き(文字は輪郭の図形にする)、そのページの描画の命令を EMF の記録に置き換える。
/// 線・面・曲線・切り抜き・線の太さと破線と色はそのまま。貼り込んだ画像と透明度は入らない
public enum MetafileExport {
    public static func emfData(renderer: GraphRenderer, rect: CGRect? = nil) -> Data {
        var outlined = renderer
        outlined.options.textAsPaths = true
        let pdf = GraphExporter.pdfData(renderer: outlined, rect: rect)
        return emf(fromPDF: pdf) ?? Data()
    }

    /// PDF の 1 ページ目を EMF にする
    public static func emf(fromPDF data: Data) -> Data? {
        guard let provider = CGDataProvider(data: data as CFData), let doc = CGPDFDocument(provider),
              let page = doc.page(at: 1) else { return nil }
        let box = page.getBoxRect(.mediaBox)
        let w = EMFWriter(widthPoints: Double(box.width), heightPoints: Double(box.height))
        guard let content = CGPDFContentStreamCreateWithPage(page) as CGPDFContentStreamRef?,
              let table = CGPDFOperatorTableCreate() else { return nil }
        PDFToEMF.install(table)
        let state = PDFToEMF(writer: w, pageHeight: Double(box.height))
        let info = Unmanaged.passUnretained(state).toOpaque()
        let scanner = CGPDFScannerCreate(content, table, info)
        CGPDFScannerScan(scanner)
        CGPDFScannerRelease(scanner)
        CGPDFContentStreamRelease(content)
        return w.finish()
    }
}

/// EMF の記録を並べる
final class EMFWriter {
    private(set) var body = Data()
    private(set) var records = 0
    /// 0.01 mm を論理単位にする(y は下向き)
    let widthUnits: Int32, heightUnits: Int32
    /// 参照の装置(96 dpi の画面)
    let deviceWidth: Int32 = 1920, deviceHeight: Int32 = 1080, deviceMMWidth: Int32 = 508, deviceMMHeight: Int32 = 286

    init(widthPoints: Double, heightPoints: Double) {
        widthUnits = Int32((widthPoints * 2540 / 72).rounded())
        heightUnits = Int32((heightPoints * 2540 / 72).rounded())
        record(17, [8])                                  // SETMAPMODE MM_ANISOTROPIC
        record(10, [0, 0])                               // SETWINDOWORGEX
        record(9, [widthUnits, heightUnits])             // SETWINDOWEXTEX
        record(12, [0, 0])                               // SETVIEWPORTORGEX
        record(11, [devX(widthUnits), devY(heightUnits)]) // SETVIEWPORTEXTEX
        record(18, [1])                                  // SETBKMODE TRANSPARENT
    }

    func devX(_ u: Int32) -> Int32 { Int32((Double(u) / 100 * Double(deviceWidth) / Double(deviceMMWidth)).rounded()) }
    func devY(_ u: Int32) -> Int32 { Int32((Double(u) / 100 * Double(deviceHeight) / Double(deviceMMHeight)).rounded()) }

    func record(_ type: UInt32, _ values: [Int32]) {
        var d = Data()
        d.append(le: type)
        d.append(le: UInt32(8 + values.count * 4))
        for v in values { d.append(le: v) }
        body.append(d); records += 1
    }

    func record(_ type: UInt32, raw: Data) {
        var d = Data()
        d.append(le: type)
        d.append(le: UInt32(8 + raw.count))
        d.append(raw)
        body.append(d); records += 1
    }

    func finish() -> Data {
        record(14, [0, 16, 20])   // EOF(パレットなし)
        var h = Data()
        let headerSize: UInt32 = 108
        h.append(le: UInt32(1)); h.append(le: headerSize)
        for v in [0, 0, devX(widthUnits) - 1, devY(heightUnits) - 1] { h.append(le: Int32(v)) }   // rclBounds(装置の点)
        for v in [0, 0, widthUnits, heightUnits] { h.append(le: v) }                                // rclFrame(0.01 mm)
        h.append(le: UInt32(0x464D4520))                    // " EMF"
        h.append(le: UInt32(0x10000))                       // 版
        h.append(le: UInt32(Int(headerSize) + body.count))  // 全体のバイト数
        h.append(le: UInt32(records + 1))                   // 記録の数(見出しを含む)
        h.append(le: UInt16(3)); h.append(le: UInt16(0))    // 使う番号の数(0 と ペン・ブラシ)
        h.append(le: UInt32(0)); h.append(le: UInt32(0))    // 説明なし
        h.append(le: UInt32(0))                             // パレットなし
        h.append(le: deviceWidth); h.append(le: deviceHeight)
        h.append(le: deviceMMWidth); h.append(le: deviceMMHeight)
        h.append(le: UInt32(0)); h.append(le: UInt32(0)); h.append(le: UInt32(0))   // ピクセル形式なし・OpenGL なし
        h.append(le: deviceMMWidth * 1000); h.append(le: deviceMMHeight * 1000)       // マイクロメートル
        return h + body
    }
}

/// PDF の描画の命令を順に受けて EMF の記録にする
final class PDFToEMF {
    struct GState {
        var ctm = CGAffineTransform.identity
        var stroke: (Double, Double, Double) = (0, 0, 0)
        var fill: (Double, Double, Double) = (0, 0, 0)
        var lineWidth = 1.0
        var cap = 0, join = 0
        var dash: [Double] = []
    }
    enum Seg { case move(CGPoint), line(CGPoint), curve(CGPoint, CGPoint, CGPoint), close }

    let w: EMFWriter
    let pageHeight: Double
    var gs = GState()
    var stack: [GState] = []
    var path: [Seg] = []
    var current = CGPoint.zero
    var pendingClip: Int32? = nil   // 1: 0 でない巻き数、2: 奇偶

    init(writer: EMFWriter, pageHeight: Double) {
        self.w = writer
        self.pageHeight = pageHeight
    }

    /// ページの点(y 上向き)→ 論理単位(0.01 mm、y 下向き)
    func unit(_ p: CGPoint) -> (Int32, Int32) {
        let q = p.applying(gs.ctm)
        return (Int32((Double(q.x) * 2540 / 72).rounded()), Int32(((pageHeight - Double(q.y)) * 2540 / 72).rounded()))
    }

    var scale: Double {
        let t = gs.ctm
        return Swift.max(sqrt(Double(t.a * t.d - t.b * t.c).magnitude), 1e-9)
    }

    func colorref(_ c: (Double, Double, Double)) -> Int32 {
        func b(_ v: Double) -> Int32 { Int32((Swift.max(0, Swift.min(1, v)) * 255).rounded()) }
        return b(c.0) | (b(c.1) << 8) | (b(c.2) << 16)
    }

    // MARK: - 記録

    func emitPath() {
        w.record(59, [])   // BEGINPATH
        var pts: [(Int32, Int32)] = []
        var kind: UInt32 = 0   // 6: 線、5: 曲線
        func flush() {
            guard !pts.isEmpty else { return }
            var d = Data()
            let xs = pts.map(\.0), ys = pts.map(\.1)
            for v in [xs.min()!, ys.min()!, xs.max()!, ys.max()!] { d.append(le: v) }
            d.append(le: UInt32(pts.count))
            for p in pts { d.append(le: p.0); d.append(le: p.1) }
            w.record(kind, raw: d)
            pts = []
        }
        for s in path {
            switch s {
            case .move(let p):
                flush()
                let u = unit(p); w.record(27, [u.0, u.1])
            case .line(let p):
                if kind != 6 { flush(); kind = 6 }
                pts.append(unit(p))
            case .curve(let a, let b, let c):
                if kind != 5 { flush(); kind = 5 }
                pts.append(unit(a)); pts.append(unit(b)); pts.append(unit(c))
            case .close:
                flush()
                w.record(61, [])
            }
        }
        flush()
        w.record(60, [])   // ENDPATH
    }

    func bounds() -> [Int32] {
        [0, 0, w.devX(w.widthUnits), w.devY(w.heightUnits)]
    }

    func paint(stroke: Bool, fill: Bool, evenOdd: Bool) {
        defer { path = [] }
        if let mode = pendingClip {
            emitPath()
            w.record(19, [mode])     // SETPOLYFILLMODE
            w.record(67, [1])        // SELECTCLIPPATH RGN_AND
            pendingClip = nil
            if !stroke && !fill { return }
        }
        guard !path.isEmpty, stroke || fill else { return }
        if fill {
            var d = Data()
            d.append(le: UInt32(2)); d.append(le: UInt32(0)); d.append(le: colorref(gs.fill)); d.append(le: UInt32(0))
            w.record(39, raw: d)              // CREATEBRUSHINDIRECT(2 番)
            w.record(37, [2])                  // SELECTOBJECT
        } else {
            w.record(37, [Int32(bitPattern: 0x8000_0005)])   // NULL_BRUSH
        }
        if stroke {
            let width = UInt32(Swift.max((gs.lineWidth * scale * 2540 / 72).rounded(), 1))
            var style: UInt32 = 0x10000   // PS_GEOMETRIC
            style |= [0x200, 0x0, 0x100][Swift.max(0, Swift.min(gs.cap, 2))]       // 平・丸・四角
            style |= [0x2000, 0x0, 0x1000][Swift.max(0, Swift.min(gs.join, 2))]    // マイター・丸・面取り
            let entries = gs.dash.map { UInt32(Swift.max(($0 * scale * 2540 / 72).rounded(), 1)) }
            if !entries.isEmpty { style |= 7 }   // PS_USERSTYLE
            var d = Data()
            d.append(le: UInt32(1))                             // ペンの番号
            for _ in 0..<4 { d.append(le: UInt32(0)) }          // 模様のビットマップなし
            d.append(le: style); d.append(le: width)
            d.append(le: UInt32(0)); d.append(le: colorref(gs.stroke)); d.append(le: UInt32(0))
            d.append(le: UInt32(entries.count))
            for e in entries { d.append(le: e) }
            w.record(95, raw: d)               // EXTCREATEPEN(1 番)
            w.record(37, [1])
        } else {
            w.record(37, [Int32(bitPattern: 0x8000_0008)])   // NULL_PEN
        }
        w.record(19, [evenOdd ? 1 : 2])
        emitPath()
        w.record(stroke && fill ? 63 : (stroke ? 64 : 62), bounds())
        w.record(37, [Int32(bitPattern: 0x8000_0007)])   // BLACK_PEN
        w.record(37, [Int32(bitPattern: 0x8000_0000)])   // WHITE_BRUSH
        if stroke { w.record(40, [1]) }
        if fill { w.record(40, [2]) }
    }

    // MARK: - PDF の命令

    static func popNumbers(_ s: CGPDFScannerRef, _ n: Int) -> [Double]? {
        var out: [Double] = []
        for _ in 0..<n {
            var v: CGPDFReal = 0
            guard CGPDFScannerPopNumber(s, &v) else { return nil }
            out.append(Double(v))
        }
        return out.reversed()
    }

    static func state(_ info: UnsafeMutableRawPointer?) -> PDFToEMF {
        Unmanaged<PDFToEMF>.fromOpaque(info!).takeUnretainedValue()
    }

    /// 色(sRGB・グレー・CMYK)
    static func setColor(_ sc: CGPDFScannerRef, _ i: UnsafeMutableRawPointer?, fill: Bool) {
        var vals: [Double] = []
        var v: CGPDFReal = 0
        while vals.count < 4, CGPDFScannerPopNumber(sc, &v) { vals.append(Double(v)) }
        vals.reverse()
        let c: (Double, Double, Double)
        switch vals.count {
        case 1: c = (vals[0], vals[0], vals[0])
        case 3: c = (vals[0], vals[1], vals[2])
        case 4: c = ((1 - vals[0]) * (1 - vals[3]), (1 - vals[1]) * (1 - vals[3]), (1 - vals[2]) * (1 - vals[3]))
        default: return
        }
        if fill { PDFToEMF.state(i).gs.fill = c } else { PDFToEMF.state(i).gs.stroke = c }
    }

    static func install(_ t: CGPDFOperatorTableRef) {
        CGPDFOperatorTableSetCallback(t, "q") { _, i in let s = PDFToEMF.state(i); s.stack.append(s.gs); s.w.record(33, []) }
        CGPDFOperatorTableSetCallback(t, "Q") { _, i in
            let s = PDFToEMF.state(i)
            if let g = s.stack.popLast() { s.gs = g }
            s.w.record(34, [-1])
        }
        CGPDFOperatorTableSetCallback(t, "cm") { sc, i in
            guard let n = PDFToEMF.popNumbers(sc, 6) else { return }
            let s = PDFToEMF.state(i)
            s.gs.ctm = CGAffineTransform(a: n[0], b: n[1], c: n[2], d: n[3], tx: n[4], ty: n[5]).concatenating(s.gs.ctm)
        }
        CGPDFOperatorTableSetCallback(t, "w") { sc, i in if let n = PDFToEMF.popNumbers(sc, 1) { PDFToEMF.state(i).gs.lineWidth = n[0] } }
        CGPDFOperatorTableSetCallback(t, "J") { sc, i in if let n = PDFToEMF.popNumbers(sc, 1) { PDFToEMF.state(i).gs.cap = Int(n[0]) } }
        CGPDFOperatorTableSetCallback(t, "j") { sc, i in if let n = PDFToEMF.popNumbers(sc, 1) { PDFToEMF.state(i).gs.join = Int(n[0]) } }
        CGPDFOperatorTableSetCallback(t, "d") { sc, i in
            var phase: CGPDFReal = 0
            _ = CGPDFScannerPopNumber(sc, &phase)
            var arr: CGPDFArrayRef?
            guard CGPDFScannerPopArray(sc, &arr), let a = arr else { return }
            var dash: [Double] = []
            for k in 0..<CGPDFArrayGetCount(a) {
                var v: CGPDFReal = 0
                if CGPDFArrayGetNumber(a, k, &v) { dash.append(Double(v)) }
            }
            PDFToEMF.state(i).gs.dash = dash.allSatisfy({ $0 <= 0 }) ? [] : dash
        }
        CGPDFOperatorTableSetCallback(t, "rg") { sc, i in PDFToEMF.setColor(sc, i, fill: true) }
        CGPDFOperatorTableSetCallback(t, "RG") { sc, i in PDFToEMF.setColor(sc, i, fill: false) }
        CGPDFOperatorTableSetCallback(t, "g") { sc, i in PDFToEMF.setColor(sc, i, fill: true) }
        CGPDFOperatorTableSetCallback(t, "G") { sc, i in PDFToEMF.setColor(sc, i, fill: false) }
        CGPDFOperatorTableSetCallback(t, "k") { sc, i in PDFToEMF.setColor(sc, i, fill: true) }
        CGPDFOperatorTableSetCallback(t, "K") { sc, i in PDFToEMF.setColor(sc, i, fill: false) }
        CGPDFOperatorTableSetCallback(t, "sc") { sc, i in PDFToEMF.setColor(sc, i, fill: true) }
        CGPDFOperatorTableSetCallback(t, "SC") { sc, i in PDFToEMF.setColor(sc, i, fill: false) }
        CGPDFOperatorTableSetCallback(t, "scn") { sc, i in PDFToEMF.setColor(sc, i, fill: true) }
        CGPDFOperatorTableSetCallback(t, "SCN") { sc, i in PDFToEMF.setColor(sc, i, fill: false) }
        // 道筋
        CGPDFOperatorTableSetCallback(t, "m") { sc, i in
            guard let n = PDFToEMF.popNumbers(sc, 2) else { return }
            let s = PDFToEMF.state(i); s.current = CGPoint(x: n[0], y: n[1]); s.path.append(.move(s.current))
        }
        CGPDFOperatorTableSetCallback(t, "l") { sc, i in
            guard let n = PDFToEMF.popNumbers(sc, 2) else { return }
            let s = PDFToEMF.state(i); s.current = CGPoint(x: n[0], y: n[1]); s.path.append(.line(s.current))
        }
        CGPDFOperatorTableSetCallback(t, "c") { sc, i in
            guard let n = PDFToEMF.popNumbers(sc, 6) else { return }
            let s = PDFToEMF.state(i)
            s.path.append(.curve(CGPoint(x: n[0], y: n[1]), CGPoint(x: n[2], y: n[3]), CGPoint(x: n[4], y: n[5])))
            s.current = CGPoint(x: n[4], y: n[5])
        }
        CGPDFOperatorTableSetCallback(t, "v") { sc, i in
            guard let n = PDFToEMF.popNumbers(sc, 4) else { return }
            let s = PDFToEMF.state(i)
            s.path.append(.curve(s.current, CGPoint(x: n[0], y: n[1]), CGPoint(x: n[2], y: n[3])))
            s.current = CGPoint(x: n[2], y: n[3])
        }
        CGPDFOperatorTableSetCallback(t, "y") { sc, i in
            guard let n = PDFToEMF.popNumbers(sc, 4) else { return }
            let s = PDFToEMF.state(i)
            let end = CGPoint(x: n[2], y: n[3])
            s.path.append(.curve(CGPoint(x: n[0], y: n[1]), end, end))
            s.current = end
        }
        CGPDFOperatorTableSetCallback(t, "h") { _, i in PDFToEMF.state(i).path.append(.close) }
        CGPDFOperatorTableSetCallback(t, "re") { sc, i in
            guard let n = PDFToEMF.popNumbers(sc, 4) else { return }
            let s = PDFToEMF.state(i)
            let x = n[0], y = n[1], ww = n[2], hh = n[3]
            s.path += [.move(CGPoint(x: x, y: y)), .line(CGPoint(x: x + ww, y: y)), .line(CGPoint(x: x + ww, y: y + hh)),
                       .line(CGPoint(x: x, y: y + hh)), .close]
            s.current = CGPoint(x: x, y: y)
        }
        // 塗る・線を引く
        CGPDFOperatorTableSetCallback(t, "S") { _, i in PDFToEMF.state(i).paint(stroke: true, fill: false, evenOdd: false) }
        CGPDFOperatorTableSetCallback(t, "s") { _, i in let s = PDFToEMF.state(i); s.path.append(.close); s.paint(stroke: true, fill: false, evenOdd: false) }
        CGPDFOperatorTableSetCallback(t, "f") { _, i in PDFToEMF.state(i).paint(stroke: false, fill: true, evenOdd: false) }
        CGPDFOperatorTableSetCallback(t, "F") { _, i in PDFToEMF.state(i).paint(stroke: false, fill: true, evenOdd: false) }
        CGPDFOperatorTableSetCallback(t, "f*") { _, i in PDFToEMF.state(i).paint(stroke: false, fill: true, evenOdd: true) }
        CGPDFOperatorTableSetCallback(t, "B") { _, i in PDFToEMF.state(i).paint(stroke: true, fill: true, evenOdd: false) }
        CGPDFOperatorTableSetCallback(t, "B*") { _, i in PDFToEMF.state(i).paint(stroke: true, fill: true, evenOdd: true) }
        CGPDFOperatorTableSetCallback(t, "b") { _, i in let s = PDFToEMF.state(i); s.path.append(.close); s.paint(stroke: true, fill: true, evenOdd: false) }
        CGPDFOperatorTableSetCallback(t, "b*") { _, i in let s = PDFToEMF.state(i); s.path.append(.close); s.paint(stroke: true, fill: true, evenOdd: true) }
        CGPDFOperatorTableSetCallback(t, "n") { _, i in PDFToEMF.state(i).paint(stroke: false, fill: false, evenOdd: false) }
        CGPDFOperatorTableSetCallback(t, "W") { _, i in PDFToEMF.state(i).pendingClip = 2 }
        CGPDFOperatorTableSetCallback(t, "W*") { _, i in PDFToEMF.state(i).pendingClip = 1 }
    }
}

extension Data {
    mutating func append<T: FixedWidthInteger>(le v: T) {
        var x = v.littleEndian
        Swift.withUnsafeBytes(of: &x) { append(contentsOf: $0) }
    }
}
