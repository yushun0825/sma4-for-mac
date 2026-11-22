import Foundation
import Testing
@testable import Sma4Core

/// 読み書きと描き方の決まりを残すテスト
@Suite("読み書きと描き方の決まり")
struct FormatBehaviorTests {
    /// 曲線の種類ごとに、範囲を (始め, 終わり) にした系列を 1 つずつ持つ SMP
    func project(_ items: [(Series.Kind, Double, Double)]) -> SMPProject {
        var p = SMPProject()
        var g = Graph.makeDefault()
        g.axes[0].from = -2; g.axes[0].to = 9
        g.axes[1].from = 0; g.axes[1].to = 30
        for (k, item) in items.enumerated() {
            let name = "R\(k).DAT"
            p.setDataFile(DataFile(name: name, timestamp: "2026-11-22 12:00:00", lines: (1...5).map { "\($0) \(1 + 2 * $0)" }))
            var s = Series(name: name)
            s.kind = item.0
            s.kindRaw = item.0.rawValue
            s.curveStart = item.1
            s.curveEnd = item.2
            g.series.append(s)
        }
        p.graphs = [g]
        return p
    }

    @Test func curveRangeEndIsAtLeastStartPlusOne() throws {
        let p = project([(.polynomialLSQ, 2, 2), (.polynomialLSQ, 4, 2), (.expLSQ, 0, 0), (.spline, 0, 0),
                         (.function, -1, -1), (.normal, 0, 0), (.polynomialLSQ, 50, 200)])
        let back = try SMPReader.read(data: SMPWriter.data(for: p, now: fixedNow))
        let ranges = back.graphs[0].series.map { [$0.curveStart, $0.curveEnd] }
        #expect(ranges == [[2, 3], [4, 5], [0, 1], [0, 1], [-1, 0], [0, 0], [50, 200]])
        // 保存すると直した値が書かれる
        let text = SMPWriter.text(for: back, now: fixedNow)
        #expect(text.contains("0 101 1 0 4.000000e+00 5.000000e+00 "))
        // 2 回目からは変わらない
        let again = try SMPReader.read(data: SMPWriter.data(for: back, now: fixedNow))
        #expect(SMPWriter.text(for: again, now: fixedNow) == text)
    }

    @Test func curveIsDrawnOverTheNormalizedRange() throws {
        var p = project([(.polynomialLSQ, 0, 0)])
        p.graphs[0].series[0].lsqOrder = 1
        let d = SeriesEvaluator.evaluate(graph: p.graphs[0], project: p)[0]
        #expect(d.curve.first?.x == 0 && d.curve.last?.x == 1)
    }

    @Test func splineModes() throws {
        var p = project([(.spline, 2, 4), (.spline, 6, 8), (.spline, -1, 7), (.spline, 2, 4), (.spline, 2, 4)])
        for k in 0..<3 { p.graphs[0].series[k].lsqOrder = 0 }   // 3 次スプライン
        p.graphs[0].series[3].lsqOrder = 1   // パラメトリックは範囲を使わない
        p.graphs[0].series[4].lsqOrder = 3   // 0〜2 以外は描かない
        let d = SeriesEvaluator.evaluate(graph: p.graphs[0], project: p)
        func drawn(_ k: Int) -> [Double] { d[k].curve.filter { $0.y.isFinite }.map(\.x) }
        // 3 次スプラインは範囲とデータの範囲の重なりだけ
        #expect(drawn(0).min() == 2 && drawn(0).max() == 4)
        #expect(drawn(1).isEmpty)
        #expect((drawn(2).min() ?? 0) >= 1 && (drawn(2).max() ?? 9) <= 5 && drawn(2).count > 40)
        #expect(abs((drawn(3).min() ?? 0) - 1) < 1e-9 && abs((drawn(3).max() ?? 0) - 5) < 1e-9)
        #expect(d[4].curve.isEmpty)
    }

    func axis(_ from: Double, _ to: Double, _ inc: Double, idig: Int = 5, ddig: Int = 5) -> AxisSpec {
        var a = AxisSpec()
        a.from = from; a.to = to; a.increment = inc; a.integerDigits = idig; a.decimalDigits = ddig
        return a
    }
    func labels(_ a: AxisSpec, plain: Bool = false) -> [String] {
        AxisScale(a, plainLogDecades: plain).ticks().filter(\.isMajor).compactMap(\.label)
    }

    /// 倍率(×10^n)は From・To と目盛の間隔の桁で決まり、ファイルのゲタのオーダーは使わない
    @Test func automaticGetta() {
        #expect(AxisScale(axis(0, 99999, 20000)).gettaExponent == nil)
        #expect(labels(axis(0, 99999, 20000)) == ["0", "20000", "40000", "60000", "80000"])
        #expect(AxisScale(axis(0, 1e6, 2e5)).gettaExponent == 6)
        #expect(labels(axis(0, 1e6, 2e5)) == ["0", "0.2", "0.4", "0.6", "0.8", "1"])
        #expect(AxisScale(axis(0, 100000, 20000)).gettaExponent == 5)
        #expect(AxisScale(axis(0, 1e-5, 2e-6)).gettaExponent == -6)
        #expect(labels(axis(0, 1e-5, 2e-6)) == ["0", "2", "4", "6", "8", "10"])
        #expect(AxisScale(axis(0, 5000, 1000, idig: 3)).gettaExponent == 3)
        #expect(AxisScale(axis(0, 1e-4, 2e-5)).gettaExponent == nil)
        #expect(labels(axis(0, 1e-4, 2e-5)) == ["0", "0.00002", "0.00004", "0.00006", "0.00008", "0.0001"])
        #expect(AxisScale(axis(0, 0.01, 0.002, ddig: 2)).gettaExponent == -3)
        #expect(AxisScale(axis(-1e6, 1e6, 5e5)).gettaExponent == 6)
        #expect(labels(axis(-1e6, 1e6, 5e5)) == ["-1", "-0.5", "0", "0.5", "1"])
        #expect(labels(axis(5e5, 6e5, 2e4)) == ["5", "5.2", "5.4", "5.6", "5.8", "6"])
        #expect(labels(axis(123456, 123460, 1)) == ["1.23456", "1.23457", "1.23458", "1.23459", "1.2346"])
        #expect(AxisScale(axis(0, 1e-4, 2.5e-5)).gettaExponent == nil)
        #expect(AxisScale(axis(0, 3e5, 1e5, idig: 6)).gettaExponent == nil)
        var stored = axis(0, 5000, 1000)
        stored.gettaOrder = 1000
        #expect(labels(stored) == ["0", "1000", "2000", "3000", "4000", "5000"])
    }

    /// 「0 は消さない」「0.0 は 0」「+ を付ける」「小数部の桁数」
    @Test func labelOptions() {
        var a = axis(0, 1, 0.25)
        #expect(labels(a) == ["0", "0.25", "0.5", "0.75", "1"])
        a.zeroPadding = true; a.decimalDigits = 3
        #expect(labels(a) == ["0", "0.250", "0.500", "0.750", "1.000"])
        a.zeroAsInteger = false; a.decimalDigits = 2
        #expect(labels(a) == ["0.00", "0.25", "0.50", "0.75", "1.00"])
        var b = axis(-1, 1, 0.5)
        b.plusSign = true
        #expect(labels(b) == ["-1", "-0.5", "0", "+0.5", "+1"])
        var c = axis(-0.005, 0.15, 0.05)
        c.zeroPadding = true; c.decimalDigits = 2
        #expect(labels(c) == ["0", "0.05", "0.10", "0.15"])
    }

    /// 目盛変換: 数字だけを式で計算し直す。x が目盛の値(倍率で割ったあと)、y は 0。計算できない値は 1e301 の印
    @Test func tickTransform() {
        var a = axis(-2, 6, 1)
        a.transformEnabled = true; a.transformExpression = "x*2"
        #expect(labels(a) == ["-4", "-2", "0", "2", "4", "6", "8", "10", "12"])
        var b = axis(0, 10, 2)
        b.transformEnabled = true; b.transformExpression = "x/3"
        #expect(labels(b) == ["0", "0.66667", "1.33333", "2", "2.66667", "3.33333"])
        b.transformExpression = "sqrt(x)"
        #expect(labels(b) == ["0", "1.41421", "2", "2.44949", "2.82843", "3.16228"])
        b.transformExpression = "x*12345.678"
        #expect(labels(b).last == "123456.78")
        b.transformExpression = "x*1e20"
        #expect(labels(b)[1] == "200000000000000000000")
        var c = axis(-10, 10, 5)
        c.transformEnabled = true; c.transformExpression = "log(x)"
        let bad = "1." + String(repeating: "0", count: 39) + "e+301"
        #expect(labels(c) == [bad, bad, bad, "0.69897", "1"])
        c.transformExpression = "y+100"
        #expect(labels(c) == ["100", "100", "100", "100", "100"])
        // 印を外すと式は使わない(式は残る)
        c.transformEnabled = false
        #expect(labels(c) == ["-10", "-5", "0", "5", "10"])
        // 倍率で割った値に式をかける
        var d = axis(0, 1e20, 2e19)
        d.transformEnabled = true; d.transformExpression = "x*1e-7"
        #expect(labels(d) == ["0", "0", "0", "0", "0", "0"])
        // 対数(指数で書く)には効かず、対数(値で書く)には効く
        var e = axis(1, 1000, 1)
        e.scaleType = .logExponent; e.transformEnabled = true; e.transformExpression = "x*10"
        #expect(labels(e) == ["10^0@", "10^1@", "10^2@", "10^3@"])
        e.scaleType = .logNormal; e.transformExpression = "x*2"
        #expect(labels(e).prefix(4) == ["2", "4", "6", "8"])
    }

    /// 目盛変換の式は副目盛の行の次の行、使うかどうかは 2 行目の 12 個目。U・R を共通にしても式は軸ごと
    @Test func transformIsReadAndWritten() throws {
        var p = project([(.normal, 0, 0)])
        p.graphs[0].axes[0].transformEnabled = true
        p.graphs[0].axes[0].transformExpression = "x*2"
        p.graphs[0].axes[3].transformExpression = "y+100"
        let text = SMPWriter.text(for: p, now: fixedNow)
        #expect(text.contains("2 0 1 1 1 1 0 0 0 300 100 1\r\n"))
        #expect(text.contains("\r\nx*2\r\n[AXIS-1]"))
        let back = try SMPReader.read(data: SMPWriter.data(for: p, now: fixedNow))
        #expect(back.graphs[0].axes[0].transformEnabled && back.graphs[0].axes[0].transformExpression == "x*2")
        #expect(!back.graphs[0].axes[3].transformEnabled && back.graphs[0].axes[3].transformExpression == "y+100")
        #expect(back.graphs[0].effectiveAxis(3).transformExpression == "y+100")
        // 開いたときに共通の軸をそろえたあとは、何度読み書きしても同じ
        let t2 = SMPWriter.text(for: back, now: fixedNow)
        #expect(SMPWriter.text(for: try SMPReader.read(text: t2), now: fixedNow) == t2)
    }

    /// 対数の 10^0・10^1 を 1・10 と書く([GRAPH] の 2 行目の 6 個目)
    @Test func plainLogDecades() throws {
        var a = axis(0.01, 1000, 1)
        a.scaleType = .logExponent
        #expect(labels(a, plain: true) == ["10^-2@", "10^-1@", "1", "10", "10^2@", "10^3@"])
        #expect(labels(a) == ["10^-2@", "10^-1@", "10^0@", "10^1@", "10^2@", "10^3@"])
        var p = project([(.normal, 0, 0)])
        p.graphs[0].plainLogDecades = true
        let text = SMPWriter.text(for: p, now: fixedNow)
        #expect(text.contains("[GRAPH]\r\n4000 2000 14000 10000\r\n100 1 0 0 1 1\r\n") || text.contains(" 0 1 1\r\n"))
        #expect(try SMPReader.read(text: text).graphs[0].plainLogDecades)
    }

    /// 他のグラフとリンク: 範囲をほかのグラフの同じ軸(と共通の反対側)に入れる。SMA の 2 行目に書くが、開くと外れる
    @Test func linkedAxes() throws {
        var p = project([(.normal, 0, 0)])
        var g2 = p.graphs[0]
        g2.series = []
        g2.axes[0].from = 0; g2.axes[0].to = 100; g2.axes[0].increment = 20; g2.axes[0].autoStep = true
        g2.axes[1].labelShiftX = -100
        p.graphs.append(g2)
        // 2 枚目の Y 軸を対数 1〜1000 にしてリンク
        p.graphs[1].axes[1].from = 1; p.graphs[1].axes[1].to = 1000; p.graphs[1].axes[1].increment = 1
        p.graphs[1].axes[1].division = 10; p.graphs[1].axes[1].scaleType = .logExponent; p.graphs[1].axes[1].autoStep = false
        p.setAxisLinked(1, true)
        GraphOps.applyLinkedAxis(&p, from: 1, axis: 1)
        for k in [1, 3] {
            let a = p.graphs[0].axes[k]
            #expect(a.from == 1 && a.to == 1000 && a.increment == 1 && a.division == 10 && a.scaleType == .logExponent && !a.autoStep)
        }
        #expect(p.graphs[0].axes[1].labelShiftX == -200)   // 範囲のほかは変えない
        #expect(p.graphs[0].axes[0].to == 9)                // ほかの軸も変えない
        let text = SMPWriter.text(for: p, now: fixedNow)
        #expect(text.hasPrefix(" Sma4Win ver. 1.1  SMA file\r\n 2 0 1 0 0 100\r\n"))
        let back = try SMPReader.read(data: SMPWriter.data(for: p, now: fixedNow))
        #expect(!back.axisLinked(1))
        #expect(back.multiGraphHeaderTail == ["0", "0", "0", "0", "100"])
    }

    /// 図: 情報の行は「画素の幅 高さ 表示の幅 高さ(0.01 mm)」、x1・y1 が左上。枠と図の 19 個目の値は絶対位置
    @Test func pictureAndAbsoluteBox() throws {
        let lines = ["2", "3", "1.000000e+01 2.000000e+01 6.000000e+01 5.000000e+01 0 0 40 100 0 3 40 1 16777215 0 0 1 30 100 1", "",
                     "10", "pic.bmp", "16 8 3000 1500",
                     "2.000000e+01 3.000000e+01 4.500000e+01 2.040000e+01 0 0 40 5000 0 10 300 1 16777215 0 0 1 30 100 1", ""]
        let objs = SMPReader.legendObjects(lines: lines)
        #expect(objs.count == 2)
        guard case .shape(let box) = objs.first, case .picture(let pic) = objs.last else { Issue.record("読めない"); return }
        #expect(box.absolutePosition && pic.shape.absolutePosition)
        #expect(pic.displaySize?.width == 3000 && pic.displaySize?.height == 1500)
        #expect(PictureObject.newInfo(pixelWidth: 16, pixelHeight: 8, widthMM: 30) == [16, 8, 3000, 1500])
        var p = project([(.normal, 0, 0)])
        p.graphs[0].left = 4000; p.graphs[0].top = 2500
        let fr = GraphRenderer.Frame(p.graphs[0])
        // 用紙の (20, 30) mm → グラフの枠の左上から (-20, 5) mm。大きさは 30 × 15 mm
        #expect(GraphRenderer.pictureRect(pic, fr) == CGRect(x: -2000, y: 500, width: 3000, height: 1500))
        let pts = try #require(GraphRenderer.shapePoints(box, fr))
        #expect(pts.0 == CGPoint(x: -3000, y: -500) && pts.1 == CGPoint(x: 2000, y: 2500))
        // 拡大率 200% なら、絶対位置のものは大きさが変わらないように見えるよう、グラフの中の値は半分
        p.graphs[0].zoom = 200
        let fr2 = GraphRenderer.Frame(p.graphs[0])
        #expect(GraphRenderer.pictureRect(pic, fr2) == CGRect(x: -1000, y: 250, width: 1500, height: 750))
        // 相対位置の図は枠の左上から
        var rel = pic
        rel.shape.absolutePosition = false
        #expect(GraphRenderer.pictureRect(rel, fr) == CGRect(x: 2000, y: 3000, width: 3000, height: 1500))
        // 書き戻しても同じ行
        #expect(SMPWriter.legendLines([.shape(box), .picture(pic)]) == lines)
    }

    /// 16bit 形式(ver. 1.5)の並び。読み直すとフォントは ×100 に戻る
    @Test func sixteenBitFormat() throws {
        var p = project([(.normal, 0, 0)])
        var t = TextObject(); t.kind = .xTitle; t.x = 6000; t.y = 11800; t.text = "Time / s"
        var o = TextObject(); o.kind = .other; o.x = 2000; o.y = 1500; o.text = "日本語"
        var box = ShapeObject(); box.objectType = 3; box.shapeType = 3; box.x1 = 90; box.y1 = 5; box.x2 = 130; box.y2 = 25
        var dot = DotObject(); dot.x = 11000; dot.y = 6000; dot.dotType = 5
        var shape = ShapeObject(); shape.x1 = 100; shape.y1 = 60
        let pic = PictureObject(path: "pic.bmp", info: PictureObject.newInfo(pixelWidth: 16, pixelHeight: 8, widthMM: 20), shape: shape)
        p.graphs[0].objects = [ObjectItem(.text(t)), ObjectItem(.text(o)), ObjectItem(.shape(box)), ObjectItem(.dot(dot)), ObjectItem(.picture(pic))]
        p.graphs[0].axes[0].transformEnabled = true; p.graphs[0].axes[0].transformExpression = "x*2"
        GraphOps.syncCommonAxes(&p.graphs[0])
        let text = SMPWriter.text16(for: p, now: fixedNow)
        let lines = text.components(separatedBy: "\r\n")
        #expect(lines[0] == " Sma4Win ver. 1.5  SMP file" && lines[2] == "" && lines[3] == "1")
        let gi = try #require(lines.firstIndex(of: "[GRAPH]"))
        #expect(lines[gi + 2] == "100 1 0 0")
        let ai = try #require(lines.firstIndex(of: "[AXIS-0]"))
        #expect(lines[ai + 2].split(separator: " ").count == 11 && lines[ai + 3].hasPrefix("-24 ") && lines[ai + 7] == "")
        let ti = try #require(lines.firstIndex(of: "[TITLE]"))
        #expect(lines[ti + 1] == "5" && lines[ti + 2] == "6000 11800 0 1" && lines[ti + 3] == "Time / s")
        #expect(lines[ti + 9] == "4900 11600 0 1" && lines[ti + 10] == "" && lines[ti + 11] == "-24 0 0 0 700 255 0 0 0 3 2 1 18")
        #expect(lines[ti + 30] == "2000 1500 0 1" && lines[ti + 31] == "日本語")
        let ri = try #require(lines.firstIndex(of: "[ARROW]"))
        #expect(lines[ri + 1] == "2")
        #expect(lines[ri + 2] == "9.000000e+01 5.000000e+00 1.300000e+02 2.500000e+01 0 0 40 500 0 3 300 1 16777215 ")
        #expect(lines[ri + 4].hasSuffix(" 0 10 300 1 16777215 pic.bmp"))
        let di = try #require(lines.firstIndex(of: "[DOT]"))
        #expect(lines[di + 1] == "1" && lines[di + 2] == "11000 6000 5 40 0 0 300 0 0 300 0 16777215 5" && lines[di + 3] == "1")
        // 読み直す: フォントは ×100、文字は矢印・点のあと、図は大きさの無い形
        let back = try SMPReader.read(text: text)
        let g = back.graphs[0]
        #expect(g.axes[0].font.height == -2400 && !g.axes[0].transformEnabled && g.axes[0].transformExpression.isEmpty)
        let kinds = g.objects.map { item -> String in
            switch item.object {
            case .shape: return "shape"
            case .picture(let q): return q.info == [0, 0, 0, 0] ? "picture0" : "picture"
            case .dot: return "dot"
            case .text(let x): return "text\(x.kind.rawValue)"
            case .raw: return "raw"
            }
        }
        #expect(kinds == ["shape", "picture0", "dot", "text4", "text8"])
        if case .text(let x) = g.objects[3].object { #expect(x.latinFont.height == -2400 && x.symbolFont.faceName == "Symbol") }
    }

    /// 線種の刻み(0.01 mm)
    @Test func dashPatterns() {
        func d(_ t: Int, _ w: Int, _ p: Int) -> [Double] { GraphRenderer.dash(t, pitch: p, width: w).map { Double($0) } }
        #expect(d(2, 10, 1000) == [500, 500])
        #expect(d(2, 60, 300) == [150, 150])
        #expect(d(2, 80, 300) == [200, 200])          // 太さ×5 = 400 がピッチより大きい
        #expect(d(2, 150, 300) == [375, 375])
        #expect(d(2, 100, 600) == [300, 300])
        #expect(d(3, 10, 1000) == [10, 990])
        #expect(d(3, 200, 300) == [200, 800])
        #expect(d(3, 40, 300) == [40, 260])
        #expect(d(3, 70, 150) == [70, 280])
        #expect(d(4, 10, 1000) == [500, 245, 10, 245])
        #expect(d(4, 200, 300) == [500, 150, 200, 150])
        // 二点鎖線: 点の中心は 2T/3 と 5T/6。太さ 10 では 661.7〜671.7 と 828.3〜838.3、太さ 200 では 2 つの点が重なる
        let a = d(5, 10, 1000)
        #expect(a.count == 6 && a[0] == 500 && Swift.abs(a[1] - 161.67) < 0.01 && a[2] == 10 && Swift.abs(a[3] - 156.67) < 0.01)
        let b = d(5, 200, 300)
        #expect(b.count == 4 && b[0] == 500 && Swift.abs(b[1] - 66.67) < 0.01 && Swift.abs(b[2] - 366.67) < 0.01)
        #expect(d(1, 40, 300).isEmpty)
    }

    /// 古い形式(1.3・1.4)と方眼のグラフの読み方
    @Test func oldVersionsAndGridFrame() throws {
        var p = project([(.normal, 0, 0)])
        p.graphs[0].axes[0].limitRange = true; p.graphs[0].axes[0].limitStart = 2000; p.graphs[0].axes[0].limitEnd = 5000
        let t15 = SMPWriter.text16(for: p, now: fixedNow)
        let t13 = t15.replacingOccurrences(of: "ver. 1.5  SMP", with: "ver. 1.3  SMP")
        // 軸の線の範囲: 1.4 はそのまま、1.3 は読まずに「限らない・0〜10000」
        let a14 = try SMPReader.read(text: t15.replacingOccurrences(of: "ver. 1.5  SMP", with: "ver. 1.4  SMP")).graphs[0].axes[0]
        #expect(a14.limitRange && a14.limitStart == 2000 && a14.limitEnd == 5000)
        let a13 = try SMPReader.read(text: t13).graphs[0].axes[0]
        #expect(!a13.limitRange && a13.limitStart == 0 && a13.limitEnd == 10000)

        // 曲線の線の行の範囲の外の数は、変えなければそのまま書き戻す
        let style = "\r\n" + SMPWriter.curveStyleFields(p.graphs[0].series[0]) + " 1\r\n"
        #expect(t13.components(separatedBy: style).count == 2)
        var q = try SMPReader.read(text: t13.replacingOccurrences(of: style, with: "\r\n-28034 179 -1837225585 14695\r\n"))
        #expect(SMPWriter.text(for: q, now: fixedNow).contains("\r\n-28034 179 -1837225585 14695 1\r\n"))
        q.graphs[0].series[0].curveColor = SMPColor(colorref: 255)
        #expect(!SMPWriter.text(for: q, now: fixedNow).contains("-28034"))

        // [OTHERS] が最後の節の古いファイル: 書くと [OTHERS] のあとの空の行は 1 つ
        let oi = try #require(t13.range(of: "[OTHERS]"))
        var end = t13[oi.upperBound...].range(of: "\r\n[").map { String(t13[..<$0.lowerBound]) } ?? t13
        while end.hasSuffix("\r\n") { end.removeLast() }
        end += "\r\n\r\n"
        let ow = SMPWriter.text(for: try SMPReader.read(text: end), now: fixedNow)
        #expect(ow.contains("\r\n\r\n[MASKS]") && !ow.contains("\r\n\r\n\r\n[MASKS]"))

        // 方眼: U・R 軸の主目盛・副目盛の「内側」を外す(外側と X・Y 軸はそのまま)。枠では外さない
        var gq = project([(.normal, 0, 0)])
        for i in 0..<4 {
            gq.graphs[0].axes[i].major.inside = true; gq.graphs[0].axes[i].major.outside = true
            gq.graphs[0].axes[i].minor.inside = true; gq.graphs[0].axes[i].minor.outside = true
        }
        gq.graphs[0].frameType = .grid
        let gb = try SMPReader.read(text: SMPWriter.text(for: gq, now: fixedNow)).graphs[0]
        #expect(gb.axes[0].major.inside && gb.axes[1].minor.inside)
        #expect(!gb.axes[2].major.inside && !gb.axes[2].minor.inside && !gb.axes[3].major.inside && !gb.axes[3].minor.inside)
        #expect(gb.axes[2].major.outside && gb.axes[3].minor.outside)
        gq.graphs[0].frameType = .box
        let bb = try SMPReader.read(text: SMPWriter.text(for: gq, now: fixedNow)).graphs[0]
        #expect(bb.axes[2].major.inside && bb.axes[3].minor.inside)

        // 軸の線の範囲は、始めが終わりより大きければ入れ替える
        gq.graphs[0].axes[1].limitStart = 3000; gq.graphs[0].axes[1].limitEnd = 2000
        let sb = try SMPReader.read(text: SMPWriter.text(for: gq, now: fixedNow)).graphs[0]
        #expect(sb.axes[1].limitStart == 2000 && sb.axes[1].limitEnd == 3000)
    }
}

/// EMF への書き出し: 記録の形(見出しの大きさと数・終わりの記録)と、線・面・文字の輪郭が入ること
@Suite("EMF")
struct EMFTests {
    @Test func structure() throws {
        let p = try SMPReader.read(data: fixtureData())
        let data = MetafileExport.emfData(renderer: GraphRenderer(project: p))
        #expect(data.count > 1000)
        func u32(_ o: Int) -> UInt32 { data.subdata(in: o..<(o + 4)).withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) } }
        #expect(u32(0) == 1 && u32(40) == 0x464D4520 && Int(u32(48)) == data.count)
        var off = 0, n = 0, types = Set<UInt32>(), last: UInt32 = 0
        while off < data.count {
            let t = u32(off), sz = Int(u32(off + 4))
            #expect(sz >= 8 && sz % 4 == 0)
            types.insert(t); last = t; n += 1; off += sz
            if sz < 8 { break }
        }
        #expect(off == data.count && Int(u32(52)) == n && last == 14)
        // 道筋・線のペン・塗りのブラシ・曲線(文字の輪郭)
        #expect(types.isSuperset(of: [59, 60, 64, 62, 95, 39, 5, 6]))
    }
}
