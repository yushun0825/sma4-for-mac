import Foundation
import Testing
@testable import Sma4Core

// 数値計算を、Sma4Core を使わずに別に計算した参照値と比べる。
// 参照値は Python の標準ライブラリだけで求めた: 線形の最小二乗とスプラインは Fraction で正確に解き、
// 対数・指数・非線形の最小二乗は Decimal(50 桁)で J^T r = 0 になるまで詰めた値。
// 非線形の問題は NIST StRD の Misra1a(保証値 b1 = 2.3894212918E+02, b2 = 5.5015643181E-04, RSS = 1.2455138894E-01)も使う。

/// 相対誤差
private func rel(_ a: Double, _ b: Double) -> Double { b == 0 ? Swift.abs(a) : Swift.abs(a - b) / Swift.abs(b) }

private func params(_ r: FitResult) -> [String: Double] {
    if case .general(_, let p) = r.model { return p }
    return [:]
}

private func linear(_ r: FitResult) -> (a0: Double, a1: Double)? {
    switch r.model {
    case .exponential(let a0, let a1), .logarithmic(let a0, let a1), .power(let a0, let a1): return (a0, a1)
    default: return nil
    }
}

@Suite("数値計算の参照値")
struct MathReferenceTests {

    // MARK: - 多項式の最小二乗

    @Test func polynomialWithLargeOffsetMatchesExactSolution() throws {
        // x = 10^6 + 0.5 i。y はちょうど表せる値(正確な解は Fraction で求めた)
        let xs = (0..<20).map { 1e6 + 0.5 * Double($0) }
        let ys: [Double] = (0..<20).map { (i: Int) -> Double in
            let noise: Double = Double((i * 37) % 11) * 0.03125
            let line: Double = 0.75 * Double(i)
            let curve: Double = 0.015625 * Double(i * i)
            return noise + line - curve
        }
        let r = try Fitting.polynomial(x: xs, y: ys, order: 2)
        guard case .polynomial(let c, _, _, _) = r.model else { Issue.record("型が違う"); return }
        let exact = [-62501508082.58891, 125001.50808270677, -0.0625]
        for (a, b) in zip(c, exact) { #expect(rel(a, b) < 1e-9, "\(a) \(b)") }
        // 曲線の値(中心をずらした係数で計算するので、x が大きくても桁が落ちない)
        for (x, y) in zip([1e6, 1e6 + 4.75, 1e6 + 9.5], [0.11785714285714285, 5.87109375, 8.804017857142858]) {
            #expect(rel(r.evaluate(x), y) < 1e-12)
        }
        #expect(Swift.abs(r.correlation - 0.9993160942069903) < 1e-12)
        #expect(rel(r.chiSquare, 0.1961701127819549) < 1e-9)
    }

    @Test func polynomialDetectsTooFewDistinctX() throws {
        // 違う x が 3 つしかない(各 100 点)。3 次は解が決まらないので、点が多くても「計算できない」にする
        let xs = (0..<300).map { Double($0 % 3) * 1e6 }
        let ys = (0..<300).map { Double($0 % 3) + 0.001 * Double($0 % 7) }
        #expect(throws: FitError.singular) { try Fitting.polynomial(x: xs, y: ys, order: 3) }
        let twoX = (0..<10000).map { Double($0 % 2) }
        #expect(throws: FitError.singular) { try Fitting.polynomial(x: twoX, y: twoX, order: 2) }
        // 2 次なら解ける。各 x での値は群の平均
        let r = try Fitting.polynomial(x: xs, y: ys, order: 2)
        for (x, m) in zip([0, 1e6, 2e6], [0.00297, 1.00299, 2.0030099999999997]) { #expect(Swift.abs(r.evaluate(x) - m) < 1e-11) }
    }

    // MARK: - 指数・対数・べき乗(直線にした座標の最小二乗)

    static let xe: [Double] = (0..<16).map { (i: Int) -> Double in 0.5 * Double(i + 1) }
    static let ye: [Double] = (0..<16).map { (i: Int) -> Double in
        let base: Double = Double(1 << (i / 2))
        let factor: Double = 1 + 0.125 * Double(i % 3)
        return base * factor
    }
    static let yl: [Double] = (0..<16).map { (i: Int) -> Double in
        let a: Double = 0.25 * Double(i)
        let b: Double = 0.125 * Double(i % 3)
        return 1 + a + b
    }
    static let yp: [Double] = (0..<16).map { (i: Int) -> Double in
        let square: Double = 0.25 * Double((i + 1) * (i + 1))
        let factor: Double = 1 + 0.0625 * Double(i % 4)
        return square * factor
    }

    @Test func expLogPowerThroughPoint() throws {
        let xe = Self.xe
        let e = try Fitting.exponential(x: xe, y: Self.ye, passThrough: (5, 70))
        let l = try Fitting.logarithmic(x: xe, y: Self.yl, passThrough: (3, 2.5))
        let p = try Fitting.power(x: xe, y: Self.yp, passThrough: (4, 4))
        let refs: [(FitResult, Double, Double, Double, Double, Double)] = [
            (e, 0.049168091435392546, 0.8398654301227932, 0.6866108661023675, 5, 70),
            (l, 0.8565666355895736, 1.495917514633688, 0.9028888269048339, 3, 2.5),
            (p, -0.874118014154433, 1.6305428620861546, 0.355259815975416, 4, 4),
        ]
        let ys = [Self.ye, Self.yl, Self.yp]
        for (k, (r, a0, a1, _, x0, y0)) in refs.enumerated() {
            let c = try #require(linear(r))
            #expect(rel(c.a0, a0) < 1e-12 && rel(c.a1, a1) < 1e-12, "\(c) \(a0) \(a1)")
            // |r| は √(SSreg/(SSreg+SSres))(直線にした座標の上、SSreg は当てはめた値の平均から)
            let lx = k == 0 ? xe : xe.map { Foundation.log($0) }
            let ly = k == 1 ? ys[k] : ys[k].map { Foundation.log($0) }
            let f = lx.map { a0 + a1 * $0 }
            let mf = f.reduce(0, +) / Double(f.count)
            let ssReg = f.reduce(0) { $0 + ($1 - mf) * ($1 - mf) }
            let ssRes = zip(ly, f).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }
            #expect(Swift.abs(r.correlation - (ssReg / (ssReg + ssRes)).squareRoot()) < 1e-12)
            #expect(rel(r.evaluate(x0), y0) < 1e-12)   // 曲線が点を通る
            #expect(r.pointCount == 16)
        }
        // 点を指定しなければ、これまでどおり(Pearson の r)
        let free = try #require(linear(try Fitting.power(x: xe, y: Self.yp)))
        #expect(rel(free.a0, 0.05827810129217666) < 1e-12 && rel(free.a1, 2.023929827238887) < 1e-12)
        #expect(e.summary.components(separatedBy: "\n").first == "*ln y=a + b x")
        // 対数を取れない点
        #expect(throws: FitError.passThroughPointOutOfDomain) { try Fitting.exponential(x: xe, y: Self.ye, passThrough: (1, 0)) }
        #expect(throws: FitError.passThroughPointOutOfDomain) { try Fitting.logarithmic(x: xe, y: Self.yl, passThrough: (-1, 2)) }
        #expect(throws: FitError.passThroughPointOutOfDomain) { try Fitting.power(x: xe, y: Self.yp, passThrough: (1, -2)) }
    }

    @Test func seriesPassesThroughPointForLogFit() throws {
        // 系列の「特定点を通る」は対数の最小二乗にも効く
        var project = SMPProject()
        project.setDataFile(DataFile(name: "log.dat", lines: zip(Self.xe, Self.yl).map { "\($0) \($1)" }))
        var g = Graph.makeDefault()
        var s = Series(name: "log.dat")
        s.kind = .logLSQ
        s.kindRaw = 5
        s.considerOutOfRange = true
        s.passThroughPoint = true
        s.passX = 3
        s.passY = 2.5
        g.series = [s]
        project.graphs = [g]
        let d = SeriesEvaluator.evaluate(graph: g, project: project)[0]
        let c = try #require(d.fit.flatMap(linear), "\(d.error ?? "")")
        #expect(rel(c.a0, 0.8565666355895736) < 1e-12 && rel(c.a1, 1.495917514633688) < 1e-12)
    }

    // MARK: - 一般関数の最小二乗

    static let misraX: [Double] = [77.6, 114.9, 141.1, 190.8, 239.9, 289.0, 332.8, 378.4, 434.8, 477.3, 536.8, 593.1, 689.1, 760.0]
    static let misraY: [Double] = [10.07, 14.73, 17.94, 23.93, 29.61, 35.18, 40.02, 44.82, 50.76, 55.05, 61.01, 66.40, 75.47, 81.78]

    @Test func generalMisra1aWithDifferenceDerivatives() throws {
        // 偏微分の式なし(差分)でも、表示する 8 桁がすべて合う
        let r = try Fitting.general(x: Self.misraX, y: Self.misraY, function: "a*(1-exp(-b*x))", initial: ["a": 500, "b": 1e-4])
        let p = params(r)
        #expect(rel(p["a"] ?? 0, 238.9421291788617) < 1e-9 && rel(p["b"] ?? 0, 0.0005501564318059136) < 1e-9, "\(p)")
        #expect(rel(r.chiSquare, 0.12455138894440551) < 1e-10)
        #expect(r.pointCount == 14)
    }

    /// 許容誤差(%)があるときの止め方(減らした一歩の二乗和の減り方が許容誤差以下で止める)。
    /// 偏微分の式あり・なしの例で、決まった結果と 9 桁まで同じ
    @Test func generalFitWithTolerance() throws {
        func fit(_ xs: [Double], _ ys: [Double], _ ders: [String], tol: Double) throws -> (Double, Double, String) {
            let r = try Fitting.general(x: xs, y: ys, function: "a*exp(b*x)", derivatives: ders, initial: ["a": 1, "b": 1], tolerancePercent: tol)
            let p = params(r)
            return (p["a"] ?? 0, p["b"] ?? 0, r.summary)
        }
        let s3 = try fit([1, 2, 3, 4], [0.87, 3.19, 7.24, 16.29], ["exp(b*x)", "a*x*exp(b*x)"], tol: 1)
        #expect(s3.2 == "*a*exp(b*x)\na=5.76931649e-01\nb=8.35951333e-01\n2.51943364e-01\n|r|=9.99059983e-01")
        let xs: [Double] = [0, 1, 2, 3, 4, 5], ys = [2.1, 2.6, 3.7, 4.9, 6.6, 9.0]
        for tol in [1.0, 0.1] {
            let r = try fit(xs, ys, ["exp(b*x)", "a*x*exp(b*x)"], tol: tol)
            #expect(String(format: "%10.8e %10.8e", r.0, r.1) == "2.00036299e+00 3.00101023e-01", "\(tol)")
        }
        for tol in [1.0, 0.01] {
            let r = try fit(xs, ys, [], tol: tol)
            #expect(String(format: "%10.8e %10.8e", r.0, r.1) == "2.00035570e+00 3.00101972e-01", "\(tol)")
            #expect(r.2.hasSuffix("\n6.62325470e-02\n|r|=9.99617411e-01"))
        }
        // 許容誤差 0 なら最小まで回す
        let fine = params(try Fitting.general(x: Self.misraX, y: Self.misraY, function: "a*(1-exp(-b*x))", initial: ["a": 500, "b": 1e-4]))
        #expect(rel(fine["a"] ?? 0, 238.9421291788617) < 1e-9)
    }

    @Test func generalFitDoesNotDependOnUnits() throws {
        // SI の単位(秒・アンペア)の小さなパラメータでも、差分の刻みと止める判定が値に比例する
        let xs = (0..<60).map { Double($0) * 2e-10 }
        let ys: [Double] = xs.enumerated().map { (i: Int, x: Double) -> Double in
            let noise: Double = 1 + 0.01 * Double(((i * 13) % 7) - 3) / 3
            return 5e-12 * exp(-x / 2e-9) * noise
        }
        for tolerance in [0.0] {
            let p = params(try Fitting.general(x: xs, y: ys, function: "a*exp(-x/b)", initial: ["a": 4e-12, "b": 1.5e-9],
                                               tolerancePercent: tolerance))
            #expect(rel(p["a"] ?? 0, 5.0011452562337454e-12) < 1e-8 && rel(p["b"] ?? 0, 2.0003188428124904e-09) < 1e-8, "\(p)")
        }
        // 1e-13 の大きさの直線(線形なので正確な解と比べる)
        let xl = (0..<20).map(Double.init)
        let yl: [Double] = xl.enumerated().map { (i: Int, x: Double) -> Double in
            let noise: Double = 1e-15 * (Double(((i * 5) % 9) - 4) / 4)
            return 2e-13 * x + 3e-14 + noise
        }
        let q = params(try Fitting.general(x: xl, y: yl, function: "a*x+b", derivatives: ["x", "1"], initial: ["a": 1e-13, "b": 1e-14]))
        #expect(rel(q["a"] ?? 0, 2.0001334586466165e-13) < 1e-9 && rel(q["b"] ?? 0, 2.98357142857144e-14) < 1e-9, "\(q)")
    }

    @Test func generalParameterLineIsCountToleranceValues() throws {
        // 初期値の行は「個数 許容誤差(%) 値 …」。古い 7 個(a〜g)も新しい 9 個(a〜i)も同じ並び。
        // 個数によらず a〜h の 8 つまでを読み、i と行に無い値は 0
        #expect(SeriesEvaluator.initialParameters("7 11 12 13 14 15 16 17 18")
                == ["a": 12, "b": 13, "c": 14, "d": 15, "e": 16, "f": 17, "g": 18, "h": 0, "i": 0])
        #expect(SeriesEvaluator.parameterLineTolerance("7 11 12 13 14 15 16 17 18") == 11)
        #expect(SeriesEvaluator.initialParameters("9 11 12 13 14 15 16 17 18 19 20")
                == ["a": 12, "b": 13, "c": 14, "d": 15, "e": 16, "f": 17, "g": 18, "h": 19, "i": 0])
        #expect(SeriesEvaluator.initialParameters("5 11 12 13 14 15 16 17 18 19 20 21")["h"] == 19)
        #expect(SeriesEvaluator.parameterLineTolerance("9 11 12 13 14 15 16 17 18 19 20") == 11)
        // 行の形でなければ既定の行(許容誤差 1 と a〜f は 1、g〜i は 0)の値
        let defaults: [String: Double] = ["a": 1, "b": 1, "c": 1, "d": 1, "e": 1, "f": 1, "g": 0, "h": 0, "i": 0]
        for bad in ["", "7", "x y", "7.5 1 2"] {
            #expect(SeriesEvaluator.initialParameters(bad) == defaults && SeriesEvaluator.parameterLineTolerance(bad) == nil, "\(bad)")
        }
        // 系列から: 古い形の行の 2 つ目は許容誤差なので、b の初期値は 3 つ目の 0.7(固定すれば 0.7 のまま)
        let xs: [Double] = [0, 0.5, 1, 1.5, 2, 2.5, 3]
        var project = SMPProject()
        project.setDataFile(DataFile(name: "e.dat", lines: xs.map { "\($0) \(0.6 * exp(0.8 * $0))" }))
        var g = Graph.makeDefault()
        var s = Series(name: "e.dat")
        s.kind = .generalLSQ
        s.kindRaw = 7
        s.considerOutOfRange = true
        s.generalFunction = "a*exp(b*x)"
        s.generalParameterLine = "7 1 0.5 0.7 1 1 1 1 0"
        s.generalFixed = ["b"]
        g.series = [s]
        project.graphs = [g]
        let d = SeriesEvaluator.evaluate(graph: g, project: project)[0]
        let p = params(try #require(d.fit, "\(d.error ?? "")"))
        #expect(p["b"] == 0.7 && rel(p["a"] ?? 0, 0.7744516493941834) < 1e-9, "\(p)")
    }

    // MARK: - ガウス関数・ローレンツ関数

    @Test(arguments: [ExtensionAnalysis.gaussian, .lorentzian])
    func peakFitMatchesReference(_ a: ExtensionAnalysis) throws {
        let k = 4 * log(2.0)
        let xs = stride(from: 0.0, through: 100, by: 0.5).map { $0 }
        let ys: [Double] = xs.enumerated().map { (i: Int, x: Double) -> Double in
            let bump: Double = 0.01 * sin(Double(i) * 1.7)
            if a == .lorentzian {
                let p1: Double = 10 / (1 + 4 * pow(x - 30, 2) / 64)
                let p2: Double = 6 / (1 + 4 * pow(x - 62, 2) / 144)
                return 2 + p1 + p2 + bump
            }
            let p1: Double = 10 * exp(-k * pow(x - 30, 2) / 64)
            let p2: Double = 6 * exp(-k * pow(x - 62, 2) / 144)
            return 2 + p1 + p2 + bump
        }
        var s = PeakFitSettings()
        s.varyOffset = true; s.precision = 1e-6  // 既定は Offset を動かさない・精度 0.1
        s.count = 2
        s.offset = 1
        s.intensity[0] = 8; s.position[0] = 28; s.width[0] = 10
        s.intensity[1] = 5; s.position[1] = 65; s.width[1] = 9
        let f = try ExtensionAnalyzer.run(a, x: xs, y: ys, settings: s, samples: []).fitted
        let got = [f.offset, f.intensity[0], f.position[0], f.width[0], f.intensity[1], f.position[1], f.width[1]]
        let ref = a == .gaussian
            ? [2.000038912619545, 9.99997247482251, 30.00000000275675, 7.999955993546724, 5.999972476946544, 61.999999996624055, 11.999889971402796]
            : [2.0000697855833627, 9.99996353886078, 30.00000311474283, 7.999903156577467, 5.999965900219553, 61.999991176244606, 11.999684564618793]
        for (g, r) in zip(got, ref) { #expect(rel(g, r) < 1e-7, "\(g) \(r)") }
    }

    @Test func peakFitInSIUnits() throws {
        // 波長(m)と小さな強度でも同じように収束する
        let k = 4 * log(2.0)
        let xs = (0...200).map { 4e-7 + 1e-9 * Double($0) }
        let ys: [Double] = xs.enumerated().map { (i: Int, x: Double) -> Double in
            let peak: Double = 3e-12 * exp(-k * pow(x - 5e-7, 2) / pow(2e-8, 2))
            return 1e-13 + peak + 1e-14 * sin(1.7 * Double(i))
        }
        var s = PeakFitSettings()
        s.varyOffset = true; s.precision = 1e-6  // 既定は Offset を動かさない・精度 0.1
        s.offset = 0; s.intensity[0] = 2e-12; s.position[0] = 4.9e-7; s.width[0] = 3e-8
        let f = try ExtensionAnalyzer.run(.gaussian, x: xs, y: ys, settings: s, samples: []).fitted
        let ref = [1.0002763869042062e-13, 2.999980456303609e-12, 5e-07, 1.9999739423322768e-08]
        for (g, r) in zip([f.offset, f.intensity[0], f.position[0], f.width[0]], ref) { #expect(rel(g, r) < 1e-7, "\(g) \(r)") }
    }

    // MARK: - スプライン

    @Test func naturalSplineMatchesExactSolution() {
        let x = [0.0, 0.7, 1.1, 2.6, 3.0, 4.2, 5.5, 6.1]
        let y = [0.0, 1.25, -0.5, 2.0, 0.75, -1.0, 0.5, 3.0]
        let c = Spline.curve(x: x, y: y, mode: .cubic, samples: [0.35, 1.0, 2.0, 3.5, 6.0], divisions: 10)
        let ref = [1.2373455823618458, -0.09119510751517707, 0.9458926126156332, -0.4816761689553896, 2.5399116642095185]
        for (p, r) in zip(c, ref) { #expect(Swift.abs(p.1 - r) < 1e-14, "\(p) \(r)") }
    }

    static let octagon: [(Double, Double)] = [(3, 0), (2, 2), (0, 3), (-2, 2), (-3, 0), (-2, -2), (0, -3), (2, -2)]

    @Test func parametricSplinesMatchExactSolution() {
        // 閉曲線は周期スプライン、開いた曲線は自然スプライン。媒介変数は点の番号(0, 1, 2, …)
        let x = Self.octagon.map(\.0), y = Self.octagon.map(\.1)
        let closed = Spline.curve(x: x, y: y, mode: .closedParametric, samples: [], divisions: 16)
        let a = 2.7142857142857144, b = 1.0535714285714286
        let closedRef: [(Double, Double)] = [(3, 0), (a, b), (2, 2), (b, a), (0, 3), (-b, a), (-2, 2), (-a, b), (-3, 0),
                                             (-a, -b), (-2, -2), (-b, -a), (0, -3), (b, -a), (2, -2), (a, -b), (3, 0)]
        #expect(closed.count == 17)
        for (p, r) in zip(closed, closedRef) { #expect(Swift.abs(p.0 - r.0) < 1e-14 && Swift.abs(p.1 - r.1) < 1e-14, "\(p) \(r)") }
        let open = Spline.curve(x: x, y: y, mode: .parametric, samples: [], divisions: 14)
        let openRef: [(Double, Double)] = [
            (3.0, 0.0), (2.596616283064239, 1.0535898316729646), (2.0, 2.0), (1.0851511508072826, 2.714230504981106),
            (0.0, 3.0), (-1.06222088629337, 2.714488148402611), (-2.0, 2.0), (-2.711267605633803, 1.0528169014084507),
            (-3.0, 0.0), (-2.7177086911714188, -1.0507557540364136), (-2.0, -2.0), (-1.0428976296805221, -2.7247938852627964),
            (0.0, -3.0), (1.0142992098935073, -2.6750687049124013), (2.0, -2.0)]
        #expect(open.count == 15)
        for (p, r) in zip(open, openRef) { #expect(Swift.abs(p.0 - r.0) < 1e-14 && Swift.abs(p.1 - r.1) < 1e-14, "\(p) \(r)") }
    }

    @Test func largeClosedSpline() {
        // 点が多い閉曲線(1 万点の円)。巡回三重対角を O(n) で解くので、n × n の行列を作らない
        let n = 10000
        let x = (0..<n).map { cos(2 * Double.pi * Double($0) / Double(n)) }
        let y = (0..<n).map { sin(2 * Double.pi * Double($0) / Double(n)) }
        let c = Spline.curve(x: x, y: y, mode: .closedParametric, samples: [], divisions: 2000)
        #expect(c.count == 2001)
        #expect(c.allSatisfy { Swift.abs(($0.0 * $0.0 + $0.1 * $0.1).squareRoot() - 1) < 1e-12 })
    }

    // MARK: - なめらかにする・ピーク

    @Test func movingAverageKeepsDigitsWithLargeOffset() {
        // 10^8 の下駄に 2^-10 刻みの変化(累積和の差では 10^-4 ほど狂う大きさ)
        let v = (0..<20000).map { 1e8 + Double($0 % 7) * 0.0009765625 }
        let m = ExtensionAnalyzer.movingAverage(v, window: 5)
        let ref: [(Int, Double)] = [(0, 100000000.00097656), (1, 100000000.00146484), (2, 100000000.00195312), (3, 100000000.00292969),
                                    (9999, 100000000.00292969), (19998, 100000000.00366211), (19999, 100000000.00358073)]
        for (i, r) in ref { #expect(Swift.abs(m[i] - r) <= r.ulp, "\(i) \(m[i]) \(r)") }
    }

    /// Peak Detect の決まり(極大・極小、差の大きい順)を総当たりで作った答えと比べる
    @Test func peakDetectionMatchesBruteForce() {
        let y: [Double] = (0..<40).map { (i: Int) -> Double in Double((i * 29) % 17) + Double((i * 7) % 5) * 0.5 }
        let x = y.indices.map(Double.init)
        var ref: [(i: Int, jump: Double)] = []
        for i in 1..<(y.count - 1) where (y[i] > y[i - 1] && y[i] > y[i + 1]) || (y[i] < y[i - 1] && y[i] < y[i + 1]) {
            ref.append((i, max(abs(y[i] - y[i - 1]), abs(y[i] - y[i + 1]))))
        }
        ref.sort { $0.jump != $1.jump ? $0.jump > $1.jump : $0.i < $1.i }
        let peaks = ExtensionAnalyzer.detectPeaks(x: x, y: y)
        #expect(peaks.count == ref.count && zip(peaks, ref).allSatisfy { $0.x == Double($1.i) && $0.y == y[$1.i] })
    }

    // MARK: - 数式の関数

    @Test func specialFunctions() throws {
        func v(_ s: String, _ x: Double = 0, _ y: Double = 0) throws -> Double { try Expression(s).evaluateScalar(x: x, y: y) }
        // B(p, q) = Γ(p)Γ(q)/Γ(p+q)。負の引数では Γ の符号がつく
        #expect(rel(try v("beta(x, y)", -0.5, 1), -2) < 1e-13)
        #expect(rel(try v("beta(x, y)", -2.5, 3.5), -Double.pi) < 1e-13)
        #expect(rel(try v("beta(x, y)", 0.5, 0.5), Double.pi) < 1e-13)
        #expect(rel(try v("beta(x, y)", 2, 3), 1.0 / 12) < 1e-13)
        #expect(rel(try v("beta(x, y)", 100, 100), 2.2087606931995024e-61) < 1e-12)
        #expect(try v("beta(x, y)", -1.5, -0.5) == 0)   // Γ(p+q) = Γ(-2) が極
        #expect(rel(try v("gamma(x)", 0.5), 1.7724538509055159) < 1e-15)
        #expect(rel(try v("gamma(x)", -0.5), -3.5449077018110318) < 1e-15)
        #expect(rel(try v("erfc(x)", 1), 0.15729920705028516) < 1e-15)
        #expect(rel(try v("erfc(x)", 5), 1.537459794428035e-12) < 1e-14)
        #expect(rel(try v("erf(x)", 0.5), 0.5204998778130465) < 1e-15)
    }

    @Test func differenceAndIntegralDefinitions() throws {
        // dif は隣の 2 点を結ぶ傾き(端は片側)、integ は台形則。x が等間隔でなくても同じ定義
        let x = [0.0, 0.1, 0.3, 0.35, 0.6]
        let y = x.map { $0 * $0 }
        let d = try Expression("dif(y)").evaluate(ExprContext(count: 5, x: x, y: y))
        for (a, b) in zip(d, [0.1, 0.3, 0.45, 0.9, 0.95]) { #expect(Swift.abs(a - b) < 1e-14) }
        let i = try Expression("integ(y)").evaluate(ExprContext(count: 5, x: x, y: y))
        for (a, b) in zip(i, [0, 0.0005, 0.0105, 0.0158125, 0.076125]) { #expect(Swift.abs(a - b) < 1e-15) }
    }

    // MARK: - 「y=」の付いた式

    @Test func assignmentPrefixIsAccepted() throws {
        #expect(Expression.body("y=a+b*ln(x)", assigning: "y") == "a+b*ln(x)")
        #expect(Expression.body("  Y = c+d*x ", assigning: "y") == "c+d*x")
        #expect(Expression.body("X=x*2", assigning: "x") == "x*2")
        #expect(Expression.body("y*2", assigning: "y") == "y*2")
        #expect(Expression.body("yy=1", assigning: "y") == "yy=1")
        #expect(Expression.body("x=1", assigning: "y") == "x=1")

        // 任意関数の系列(定数 a〜d はグラフの定数)
        var g = Graph.makeDefault()
        g.constants = [2, 3, 0.5, 0.25, 0, 0, 0, 0, 0]
        var f1 = Series(name: "CALC.DAT")
        f1.kind = .function
        f1.kindRaw = 3
        f1.transformY = true
        f1.expressionY = "y=a+b*ln(x)"
        f1.curveStart = 30
        f1.curveEnd = 220
        f1.curveDivisions = 101
        var f2 = f1
        f2.expressionY = " Y = c+d*x"
        // データの系列の変換式にも付けられる
        var data = Series(name: "d.dat")
        data.transformX = true
        data.expressionX = "X=x+1"
        data.transformY = true
        data.expressionY = "y = y*2"
        g.series = [f1, f2, data]
        var project = SMPProject()
        project.setDataFile(DataFile(name: "d.dat", lines: ["1 10", "2 20"]))
        project.graphs = [g]
        let d = SeriesEvaluator.evaluate(graph: g, project: project)
        #expect(d.allSatisfy { $0.error == nil })
        #expect(d[0].x.first == 30 && d[0].x.last == 220 && d[0].x.count == 102)
        #expect(rel(d[0].y.first ?? 0, 12.203592144986466) < 1e-14 && rel(d[0].y.last ?? 0, 18.180882639057085) < 1e-14)
        #expect(rel(d[1].y.first ?? 0, 8) < 1e-15 && rel(d[1].y.last ?? 0, 55.5) < 1e-15)
        #expect(d[2].x == [2, 3] && d[2].y == [20, 40])

        // SMP から読んでも計算でき、式の文字は書き戻すときにそのまま
        let text = fixtureSMP
            .replacingOccurrences(of: "x\na*x\n", with: "x\nY = a+b*ln(x)\n")
            .replacingOccurrences(of: "\n2.000000e+00 0.000000e+00 ", with: "\n2.000000e+00 3.000000e+00 ")
        #expect(text.contains("Y = a+b*ln(x)") && text.contains("\n2.000000e+00 3.000000e+00 "))
        let read = try SMPReader.read(text: text)
        let s = read.graphs[0].series[1]
        #expect(s.kind == .function && s.expressionY == "Y = a+b*ln(x)")
        let e = SeriesEvaluator.evaluate(graph: read.graphs[0], project: read)[1]
        #expect(e.error == nil && e.x.first == 1 && e.x.last == 1000)
        #expect(rel(e.y.first ?? 0, 2) < 1e-15 && rel(e.y.last ?? 0, 22.72326583694641) < 1e-14)
        #expect(SMPWriter.text(for: read).contains("\r\nY = a+b*ln(x)\r\n"))
    }
}
