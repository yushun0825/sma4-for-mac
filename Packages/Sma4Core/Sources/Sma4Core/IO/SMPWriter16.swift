import Foundation

/// 16bit 形式(ver. 1.5)で書く:
/// - 用紙の行は空行。系列の行は 1.8 と同じ
/// - [GRAPH] の 2 行目は 4 つ、軸の 2 行目は 11 個、フォントの高さと幅は 1/100、目盛変換の式は書かない(空行)
/// - 文字は [TITLE](X・Y・U・R 軸のタイトルの 4 つの枠のあとに、その他の文字)。位置は「x y 色 背景」、記号のフォントは無い
/// - 矢印・エラーバー・枠・図は [ARROW](19 個の値のうち 13 個と、図ならファイル名)、点は [DOT]
/// 1.8 で増えた値(文字の揃えと絶対位置・矢じりの形・枠の丸み・図の大きさ・目盛変換・リンクなど)は落ちる
extension SMPWriter {
    public static func data16(for project: SMPProject, now: Date = Date()) -> Data {
        Sma4TextEncoding.encodeSMP(text16(for: project, now: now))
    }

    public static func text16(for project: SMPProject, now: Date = Date()) -> String {
        var out: [String] = []
        let graphs = project.graphs
        if graphs.count <= 1 {
            if let g = graphs.first { out.append(contentsOf: graphLines16(g)) }
        } else {
            out.append(" Sma4Win ver. 1.1  SMA file")
            var tail = project.multiGraphHeaderTail
            while tail.count < 5 { tail.append(tail.count == 4 ? "100" : "0") }
            out.append(" " + ([String(graphs.count)] + tail.prefix(5)).joined(separator: " "))
            for (i, g) in graphs.enumerated() {
                var name = g.name.isEmpty ? "Graph\(i + 1).SMP" : g.name
                if !name.uppercased().hasSuffix(".SMP") { name += ".SMP" }
                out.append("[\(name)]")
                out.append(contentsOf: graphLines16(g))
            }
        }
        if graphs.contains(where: { $0.page.saveData }) {
            out.append(contentsOf: dataLines(project: project, now: now))
        }
        return out.joined(separator: "\r\n") + "\r\n"
    }

    /// フォントの高さと幅を 1/100 にした行(1.5 以前は pt で書く)
    static func fontLine16(_ f: LogFont) -> String {
        var g = f
        g.height /= 100
        g.width /= 100
        return g.fieldsLine
    }

    static func graphLines16(_ g: Graph) -> [String] {
        var l: [String] = [" Sma4Win ver. 1.5  SMP file", g.comment, "", String(g.series.count)]
        for s in g.series { l.append(contentsOf: seriesLines(s)) }

        l.append("[GRAPH]")
        l.append("\(g.left) \(g.top) \(g.width) \(g.height)")
        l.append("\(g.zoom) \(g.frameType.rawValue) \(b(g.zeroCommon)) \(g.graphLine2Tail.first ?? "0")")
        l.append("\(g.frameWidth) \(g.frameColor.colorref) \(g.framePitch) \(g.background.colorref)")
        l.append("")

        for i in 0..<4 {
            let a = g.axes[i]
            var line = axisLines(a, index: i)   // [AXIS-n]・1 行目・2 行目・フォント・名前・主目盛・副目盛・式
            var f2 = line[2].split(separator: " ").map(String.init)
            if f2.count > 11 { f2 = Array(f2.prefix(11)) }
            line[2] = f2.joined(separator: " ")
            line[3] = fontLine16(a.font)
            line[line.count - 1] = ""
            l.append(contentsOf: line)
        }

        // 文字
        let texts = g.objects.compactMap { item -> TextObject? in
            if case .text(let t) = item.object { return t } else { return nil }
        }
        func entry(_ t: TextObject?) -> [String] {
            guard let t else {
                return ["4900 11600 0 1", "", "-24 0 0 0 700 255 0 0 0 3 2 1 18", "Times New Roman",
                        "-24 0 0 0 700 1 0 0 128 3 2 1 17", "ＭＳ 明朝", ""]
            }
            return ["\(t.x) \(t.y) \(t.color.colorref) \(t.backgroundMode)", t.text,
                    fontLine16(t.latinFont), t.latinFont.faceName, fontLine16(t.japaneseFont), t.japaneseFont.faceName, ""]
        }
        let titles: [TextObject.Kind] = [.xTitle, .yTitle, .uTitle, .rTitle]
        var used = Set<Int>()
        var slots: [TextObject?] = []
        for k in titles {
            if let i = texts.indices.first(where: { !used.contains($0) && texts[$0].kind == k }) {
                used.insert(i); slots.append(texts[i])
            } else {
                slots.append(nil)
            }
        }
        let others = texts.indices.filter { !used.contains($0) }.map { texts[$0] }
        l.append("[TITLE]")
        l.append(String(4 + others.count))
        for t in slots { l.append(contentsOf: entry(t)) }
        for t in others { l.append(contentsOf: entry(t)) }

        // 矢印・エラーバー・枠・図
        let shapes = g.objects.compactMap { item -> (ShapeObject, String)? in
            switch item.object {
            case .shape(let s): return (s, "")
            case .picture(let p): return (p.shape, p.path)
            default: return nil
            }
        }
        l.append("[ARROW]")
        l.append(String(shapes.count))
        for (s, path) in shapes {
            let f = shapeFieldsLine(s).split(separator: " ").prefix(13).joined(separator: " ")
            l.append(f + " " + path)
            l.append("")
        }

        // 点
        let dots = g.objects.compactMap { item -> DotObject? in
            if case .dot(let d) = item.object { return d } else { return nil }
        }
        l.append("[DOT]")
        l.append(String(dots.count))
        for d in dots {
            let f: [String] = [
                "\(d.x)", "\(d.y)", "\(d.dotType)", "\(d.width)", "\(d.length)", "\(d.style)", "\(d.size)",
                "\(d.color.colorref)", "\(d.lineColor.colorref)", "\(d.pitch)", "\(d.brushStyle)",
                "\(d.brushColor.colorref)", "\(d.brushHatch)",
            ]
            l.append(f.joined(separator: " "))
            l.append(String(max(d.pointCount, 1)))
            if d.pointCount >= 2 { l.append(contentsOf: d.points) }
            l.append("")
        }

        l.append("[OTHERS]")
        l.append(g.othersCountLine)
        var consts = g.constants
        while consts.count < 9 { consts.append(0) }
        l.append(consts.prefix(9).map(e).joined(separator: " "))
        l.append(fontLine16(g.othersFont))
        l.append(g.othersFont.faceName)
        l.append("")
        l.append(contentsOf: maskLines(g))
        l.append("")
        return l
    }
}
