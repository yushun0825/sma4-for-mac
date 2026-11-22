import Foundation

/// SMP を書く(CP932・CRLF・ver. 1.8 の形)。
public enum SMPWriter {
    public static func data(for project: SMPProject, now: Date = Date()) -> Data {
        Sma4TextEncoding.encodeSMP(text(for: project, now: now))
    }

    public static func text(for project: SMPProject, now: Date = Date()) -> String {
        var out: [String] = []
        let graphs = project.graphs
        let saveData = graphs.contains { $0.page.saveData }
        if graphs.count <= 1 {
            if let g = graphs.first { out.append(contentsOf: mergedGraphLines(g)) }
        } else {
            out.append(" Sma4Win ver. 1.1  SMA file")
            var header = [String(graphs.count)]
            var tail = project.multiGraphHeaderTail
            while tail.count < 5 { tail.append(tail.count == 4 ? "100" : "0") }
            header.append(contentsOf: tail.prefix(5))
            out.append(" " + header.joined(separator: " "))
            for (i, g) in graphs.enumerated() {
                var name = g.name.isEmpty ? "Graph\(i + 1).SMP" : g.name
                if !name.uppercased().hasSuffix(".SMP") { name += ".SMP" }
                out.append("[\(name)]")
                out.append(contentsOf: mergedGraphLines(g))
            }
        }
        if saveData {
            out.append(contentsOf: dataLines(project: project, now: now))
        }
        return out.joined(separator: "\r\n") + "\r\n"
    }

    static func e(_ v: Double) -> String {
        String(format: "%e", v.isFinite ? v : 0)
    }

    static func b(_ v: Bool) -> String { v ? "1" : "0" }

    /// 曲線の線種・太さ・色・ピッチ。読んだ数が範囲の外でも、値を変えていなければ読んだままの数を書く
    static func curveStyleFields(_ s: Series) -> String {
        if let r = s.curveStyleRaw, r.count == 4, let t = Int(r[0]), let w = Int(r[1]), let c = Int(r[2]), let p = Int(r[3]),
           LineType(code: t) == s.curveLineType, w == s.curveWidth, SMPColor(colorref: c) == s.curveColor, p == s.curvePitch {
            return r.joined(separator: " ")
        }
        return "\(s.curveLineType.rawValue) \(s.curveWidth) \(s.curveColor.colorref) \(s.curvePitch)"
    }

    /// グラフの行。読んだファイルから変えていない行・値は、読んだときの文字のまま書く
    static func mergedGraphLines(_ g: Graph) -> [String] {
        let new = graphLines(g)
        guard let src = g.source.lines, let norm = g.source.normalized, src.count == norm.count else { return new }
        if new == norm { return src }
        // new と norm の最長共通部分列で行を対応させる
        let n = norm.count, m = new.count
        var dp = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                dp[i][j] = norm[i] == new[j] ? dp[i + 1][j + 1] + 1 : max(dp[i + 1][j], dp[i][j + 1])
            }
        }
        var out: [String] = []
        var i = 0, j = 0
        var pendingOld: [Int] = []
        func mergeTokens(_ oldIndex: Int, _ line: String) -> String {
            let a = src[oldIndex].components(separatedBy: " "), b = norm[oldIndex].components(separatedBy: " ")
            let c = line.components(separatedBy: " ")
            guard a.count == b.count, b.count == c.count else { return line }
            return zip(zip(a, b), c).map { pair, cur in pair.1 == cur ? pair.0 : cur }.joined(separator: " ")
        }
        while j < m {
            if i < n && norm[i] == new[j] {
                out.append(src[i]); i += 1; j += 1; pendingOld = []
            } else if i < n && dp[i + 1][j] >= dp[i][j + 1] {
                pendingOld.append(i); i += 1
            } else {
                // 消えた行の代わりに入った行は、同じ並びの値を読んだときの文字にする
                if let o = pendingOld.first { out.append(mergeTokens(o, new[j])); pendingOld.removeFirst() } else { out.append(new[j]) }
                j += 1
            }
        }
        return out
    }

    static func graphLines(_ g: Graph) -> [String] {
        var l: [String] = []
        l.append(" Sma4Win ver. 1.8  SMP file")
        l.append(g.comment)
        var page = [b(g.page.saveData), b(g.page.savePath), String(g.page.paperWidth), String(g.page.paperHeight), b(g.page.landscape)]
        var tail = g.page.tail
        while tail.count < 2 { tail.append(tail.isEmpty ? 100 : 2) }
        page.append(contentsOf: tail.prefix(2).map(String.init))
        l.append(page.joined(separator: " "))
        l.append(String(g.series.count))
        for s in g.series { l.append(contentsOf: seriesLines(s)) }

        l.append("[GRAPH]")
        l.append("\(g.left) \(g.top) \(g.width) \(g.height)")
        var gt = g.graphLine2Tail
        while gt.count < 3 { gt.append(gt.count == 1 ? "1" : "0") }
        l.append(([String(g.zoom), String(g.frameType.rawValue), b(g.zeroCommon)] + gt.prefix(3)).joined(separator: " "))
        l.append("\(g.frameWidth) \(g.frameColor.colorref) \(g.framePitch) \(g.background.colorref)")
        l.append("")

        for i in 0..<4 { l.append(contentsOf: axisLines(g.axes[i], index: i)) }

        l.append("[LEGEND]")
        l.append(String(g.objects.count))
        for item in g.objects { l.append(contentsOf: objectLines(item.object)) }

        l.append("[OTHERS]")
        l.append(g.othersCountLine)
        var consts = g.constants
        while consts.count < 9 { consts.append(0) }
        l.append(consts.prefix(9).map(e).joined(separator: " "))
        l.append(g.othersFont.fieldsLine)
        l.append(g.othersFont.faceName)
        l.append(contentsOf: g.othersTailLines.isEmpty ? [""] : g.othersTailLines)
        l.append(contentsOf: maskLines(g))
        l.append("")
        return l
    }

    /// [MASKS]: " 数"、マスクごとに "%d %le %le %le %le"(対象 xMin xMax yMin yMax。対象は 0 = すべての系列、k = k 番目の系列)、残りの行("0" と "0")
    static func maskLines(_ g: Graph) -> [String] {
        var l = ["[MASKS]", " \(g.masks.count)"]
        for m in g.masks {
            l.append("\(m.target) \(e(m.xMin)) \(e(m.xMax)) \(e(m.yMin)) \(e(m.yMax))")
        }
        l.append(contentsOf: g.maskTrailingLines)
        return l
    }

    static func seriesLines(_ s: Series) -> [String] {
        var l: [String] = []
        l.append("[\(s.name)]")
        l.append(s.path.isEmpty ? s.name : s.path)
        let kind = s.kind == .normal && s.kindRaw > 9 ? s.kindRaw : s.kind.rawValue
        l.append("\(kind) 0 \(s.errorBarX.rawValue) \(s.errorBarY.rawValue) \(s.columnX) \(s.columnY) \(s.linesRead) \(s.skipLines) \(s.maxLines) \(s.option)")
        l.append("\(s.lineWidth) \(s.lineColor.colorref) \(s.pitch) \(b(s.tabAsSpace)) \(b(s.absoluteLineCount)) \(b(s.skipCommentCount)) \(s.considerOutOfRangeValue)")
        l.append("\(s.lineType.rawValue) \(s.dotType) \(s.dotSize) \(s.dotColor.colorref)")
        l.append("\(b(s.useUAxis)) \(b(s.useRAxis)) \(max(s.readStep, 1)) \(s.horizontalAverage) \(s.verticalAverage) \(s.brushStyle) \(s.brushColor.colorref) \(s.brushHatch)")
        l.append("\(b(s.transformX)) \(b(s.transformY)) \(s.converter)")
        l.append(s.expressionX.isEmpty ? "x" : s.expressionX)
        l.append(s.expressionY.isEmpty ? "y" : s.expressionY)
        l.append("\(s.curveSpacing.rawValue) \(s.curveDivisions) \(s.lsqOrder) \(b(s.passThroughPoint)) \(e(s.curveStart)) \(e(s.curveEnd)) \(e(s.passX)) \(e(s.passY)) \(e(s.barBase))")
        l.append("\(curveStyleFields(s)) \(b(s.curveVisible))")
        if s.kind == .generalLSQ {
            l.append(s.generalParameterLine.isEmpty ? defaultGeneralParameterLine : s.generalParameterLine)
            l.append(s.generalFunction)
            var d = s.generalDerivatives
            while d.count < 9 { d.append("") }
            for (k, name) in Series.generalParameterNames.enumerated() {
                l.append("\(s.generalFixed.contains(name) ? 0 : 1)|\(d[k])")
            }
        }
        if s.kind == .extension1 || s.kind == .extension2, let a = s.extensionAnalysis {
            l.append(contentsOf: extensionLines(a, s.peakFit))
        }
        l.append(contentsOf: s.extraLines)
        l.append("")
        l.append("")
        return l
    }

    /// 新しい一般関数の初期値(許容誤差 1 %・a〜f は 1・g〜i は 0。古い既定の行を直したときと同じ)
    static let defaultGeneralParameterLine = "9 " + [1, 1, 1, 1, 1, 1, 1, 0, 0, 0].map { e(Double($0)) }.joined(separator: " ")

    /// 特殊処理(種類 8)の行。決まった書き方が分からないので、このアプリで決めた形(SMPReader.parseExtensionBlock)
    /// 特殊処理の 9 行目の後ろ(SMPReader.parseExtensionBlock の形)
    static func extensionLines(_ a: ExtensionAnalysis, _ settings: PeakFitSettings) -> [String] {
        guard a.usesFittingDialog else { return ["0"] }
        let s = settings.normalized
        func f(_ x: Double) -> String { String(format: "%f", x.isFinite ? x : 0) }
        func g(_ x: Double) -> String { String(format: "%g", x.isFinite ? x : 0) }
        var l = [String(2 + s.count), f(s.precision), "\(b(s.varyOffset)) \(f(s.offset))"]
        for k in 0..<s.count {
            l.append("\(b(s.varyIntensity[k])) \(g(s.intensity[k])) \(b(s.varyPosition[k])) \(g(s.position[k])) \(b(s.varyWidth[k])) \(g(s.width[k]))")
        }
        return l
    }

    static func axisLines(_ a: AxisSpec, index: Int) -> [String] {
        var l: [String] = []
        l.append("[AXIS-\(index)]")
        let line1: [String] = [
            e(a.from), e(a.to), e(a.increment), b(a.limitRange), String(a.limitStart), String(a.limitEnd),
            String(a.crossPosition), String(a.labelCount), String(a.labelStart), String(a.labelInterval),
            b(a.plusSign), b(a.zeroPadding), b(a.zeroAsInteger), String(a.integerDigits), String(a.decimalDigits),
            e(a.gettaOrder), b(a.drawGetta),
        ]
        l.append(line1.joined(separator: " "))
        var tail = a.line2Tail
        let defaults = AxisSpec.defaultAxis(index: index).line2Tail
        while tail.count < 3 { tail.append(defaults[tail.count]) }
        let line2: [String] = [
            String(a.division), String(a.scaleType.rawValue), b(a.autoStep), b(a.commonWithOpposite),
            b(a.drawAxis), b(a.drawLabels), String(a.labelShiftX), String(a.labelShiftY),
            String(a.labelColor.colorref),
        ] + tail.prefix(3)
        l.append(line2.joined(separator: " "))
        l.append(a.font.fieldsLine)
        l.append(a.font.faceName)
        l.append(tickLine(a.major))
        l.append(tickLine(a.minor))
        l.append(a.transformExpression)   // 目盛変換の式(なければ空行)
        return l
    }

    static func tickLine(_ t: TickStyle) -> String {
        "\(b(t.inside)) \(b(t.outside)) \(t.length) \(t.width) \(t.color.colorref) \(t.pitch) \(t.style)"
    }

    /// 矢印・枠・図の 19 個の値の行(allTail なら 19 個目より後ろの値も書く)
    static func shapeFieldsLine(_ s: ShapeObject, allTail: Bool = false) -> String {
        var tail = s.tail
        if tail.isEmpty { tail = ["0"] }
        let f: [String] = [
            e(s.x1), e(s.y1), e(s.x2), e(s.y2), String(s.xReference), String(s.yReference),
            String(s.width), String(s.length), String(s.color.colorref), String(s.shapeType),
            String(s.pitch), String(s.style), String(s.shadowColor.colorref), String(s.size),
            String(s.aspect), String(s.headMode), String(s.headOpen), String(s.headClose),
        ] + (allTail ? tail : Array(tail.prefix(1)))
        return f.joined(separator: " ")
    }

    static func objectLines(_ o: GraphObject) -> [String] {
        switch o {
        case .shape(let s):
            return [String(s.objectType), shapeFieldsLine(s), ""]
        case .picture(let p):
            let info = p.info.isEmpty ? [0, 0, 0, 0] : p.info
            return [String(PictureObject.objectType), p.path, info.map(String.init).joined(separator: " "),
                    shapeFieldsLine(p.shape, allTail: true), ""]
        case .text(let t):
            let pos = ["\(t.x)", "\(t.y)", "\(t.color.colorref)", "\(t.backgroundMode)", "\(t.alignment)", b(t.absolutePosition)] + t.positionTail
            return [
                String(t.kind.rawValue),
                pos.joined(separator: " "),
                t.text,
                t.latinFont.fieldsLine, t.latinFont.faceName,
                t.japaneseFont.fieldsLine, t.japaneseFont.faceName,
                t.symbolFont.fieldsLine, t.symbolFont.faceName,
                "",
            ]
        case .dot(let d):
            var tail = d.tail
            if tail.isEmpty { tail = ["0"] }
            let f: [String] = [
                "\(d.x)", "\(d.y)", "\(d.dotType)", "\(d.width)", "\(d.length)", "\(d.style)", "\(d.size)",
                "\(d.color.colorref)", "\(d.lineColor.colorref)", "\(d.pitch)", "\(d.brushStyle)",
                "\(d.brushColor.colorref)", "\(d.brushHatch)",
            ] + tail.prefix(1)
            var l = ["9", f.joined(separator: " "), String(max(d.pointCount, 1))]
            if d.pointCount >= 2 { l.append(contentsOf: d.points) }
            l.append(d.reserved.isEmpty ? "0 0 0.0 0.0" : d.reserved)
            l.append("")
            return l
        case .raw(let type, let lines):
            return [String(type)] + lines + [""]
        }
    }

    static func dataLines(project: SMPProject, now: Date) -> [String] {
        var l: [String] = ["[DATA]"]
        var seen = Set<String>()
        var first = true
        for g in project.graphs {
            for s in g.series where s.kind != .function {
                let key = SMPProject.key(s.name)
                guard !seen.contains(key), let file = project.dataFile(named: s.name) else { continue }
                seen.insert(key)
                if !first { l.append("") }
                first = false
                let body = file.lines
                if let tail = file.unchangedHeaderTail {
                    l.append("[\(s.name)]" + tail)
                } else {
                    // 1.8 形式では見出しは名前と日時だけ
                    let stamp = file.timestamp.isEmpty ? timestamp(now) : normalizedTimestamp(file.timestamp)
                    l.append("[\(s.name)] \(stamp)")
                }
                l.append(contentsOf: body)
                l.append("[End of Data]")
            }
        }
        // 書いたデータがあれば最後に空行(データが 1 つも無ければ "[DATA]" だけ)
        if !first { l.append("") }
        return l
    }

    public static func timestamp(_ d: Date) -> String {
        let c = Calendar(identifier: .gregorian).dateComponents([.year, .month, .day, .hour, .minute, .second], from: d)
        return String(format: "%d-%d-%d %2d:%02d:%02d", c.year ?? 2000, c.month ?? 1, c.day ?? 1, c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }

    /// "1995-4-23 9:14:02" を Sma4 と同じ "1995-4-23  9:14:02" の形に揃える
    static func normalizedTimestamp(_ s: String) -> String {
        let parts = s.split(separator: " ")
        guard parts.count >= 2 else { return s }
        let t = parts[1].split(separator: ":")
        guard t.count == 3, let h = Int(t[0]), let m = Int(t[1]), let sec = Int(t[2]) else { return s }
        return String(format: "%@ %2d:%02d:%02d", String(parts[0]), h, m, sec)
    }
}

extension SMPWriter {
    /// オブジェクトを [LEGEND] と同じ書き方の行にする(コピー・貼り付け用)
    public static func legendLines(_ objects: [GraphObject]) -> [String] {
        [String(objects.count)] + objects.flatMap { objectLines($0) }
    }
}
