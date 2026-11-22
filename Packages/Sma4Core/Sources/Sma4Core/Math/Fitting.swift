import Foundation

/// 最小二乗フィットの結果
public struct FitResult: Sendable, Equatable {
    public enum Model: Sendable, Equatable {
        /// f(x) = Σ a_n x^n。center/scale は計算を安定させるための x の変換(t = (x - center) / scale)
        case polynomial(coefficients: [Double], scaledCoefficients: [Double], center: Double, scale: Double)
        /// ln y = a0 + a1 x
        case exponential(a0: Double, a1: Double)
        /// y = a0 + a1 ln x
        case logarithmic(a0: Double, a1: Double)
        /// ln y = a0 + a1 ln x
        case power(a0: Double, a1: Double)
        /// 一般関数
        case general(expression: String, parameters: [String: Double])
    }

    public var model: Model
    /// 相関係数 R
    public var correlation: Double
    /// 残差の二乗和
    public var chiSquare: Double
    public var pointCount: Int

    public func evaluate(_ x: Double) -> Double {
        switch model {
        case .polynomial(_, let sc, let center, let scale):
            let t = (x - center) / scale
            var v = 0.0
            for c in sc.reversed() { v = v * t + c }
            return v
        case .exponential(let a0, let a1):
            return Foundation.exp(a0 + a1 * x)
        case .logarithmic(let a0, let a1):
            return x > 0 ? a0 + a1 * Foundation.log(x) : .nan
        case .power(let a0, let a1):
            return x > 0 ? Foundation.exp(a0 + a1 * Foundation.log(x)) : .nan
        case .general(let src, let params):
            guard let e = try? Expression(src) else { return .nan }
            return (try? e.evaluateScalar(x: x, constants: params)) ?? .nan
        }
    }

    public func evaluate(_ xs: [Double]) -> [Double] {
        if case .general(let src, let params) = model, let e = try? Expression(src) {
            let ctx = ExprContext(count: xs.count, x: xs, y: xs, constants: params)
            return (try? e.evaluate(ctx)) ?? xs.map { _ in .nan }
        }
        return xs.map(evaluate)
    }

    /// 結果のダイアログやクリップボードに出す文: 1 行目は「*」と式、係数を "%10.8e" で 1 行ずつ、
    /// 残差の二乗平均の平方根 √(χ²/n)(指数・べき乗は ln y の上)、"|r|=" 相関係数
    public var summary: String {
        func e(_ v: Double) -> String { String(format: "%10.8e", v) }
        var lines: [String] = []
        switch model {
        case .polynomial(let coeffs, _, _, _):
            lines.append("*y=Σan x^n")
            for (i, c) in coeffs.enumerated() { lines.append("a\(i)=" + e(c)) }
        case .exponential(let a0, let a1):
            lines += ["*ln y=a + b x", "a=" + e(a0), "b=" + e(a1)]
        case .logarithmic(let a0, let a1):
            lines += ["*y=a + b ln x", "a=" + e(a0), "b=" + e(a1)]
        case .power(let a0, let a1):
            lines += ["*ln y=a + b ln x", "a=" + e(a0), "b=" + e(a1)]
        case .general(let src, let params):
            lines.append("*" + src)
            let used = (try? Expression(Expression.body(src, assigning: "y")).referencedVariables()) ?? []
            for k in Fitting.parameterNames where used.contains(k) { lines.append("\(k)=" + e(params[k] ?? 0)) }
        }
        lines.append(e(pointCount > 0 ? (chiSquare / Double(pointCount)).squareRoot() : 0))
        lines.append("|r|=" + e(Swift.abs(correlation)))
        return lines.joined(separator: "\n")
    }
}

public enum FitError: Error, LocalizedError, Equatable {
    case notEnoughPoints(needed: Int)
    case singular
    case badExpression(String)
    case didNotConverge
    /// 通る点が対数を取れない値(指数は y ≤ 0、対数は x ≤ 0、べき乗は x か y ≤ 0)
    case passThroughPointOutOfDomain

    public var errorDescription: String? {
        switch self {
        case .notEnoughPoints(let n): return "最小二乗に使えるデータ点が足りません(\(n) 点以上が必要です)。"
        case .singular: return "最小二乗の計算ができませんでした(データ点が一直線上に重なっているなど)。"
        case .badExpression(let m): return "関数の式が正しくありません: \(m)"
        case .didNotConverge: return "最小二乗が収束しませんでした。パラメータの初期値を変えてお試しください。"
        case .passThroughPointOutOfDomain:
            return "通る点の値が使えません(指数は y > 0、対数は x > 0、べき乗は x > 0 かつ y > 0 の点にしてください)。"
        }
    }
}

public enum Fitting {
    public static func format(_ v: Double) -> String {
        if v == 0 { return "0" }
        let a = Swift.abs(v)
        if a >= 1e-4 && a < 1e7 {
            var s = String(format: "%.8g", v)
            if s.contains("e") { s = String(format: "%.6e", v) }
            return s
        }
        return String(format: "%.6e", v)
    }

    /// n 次多項式。passThrough が与えられたら、その点を必ず通る。0 次は平均値。
    public static func polynomial(x: [Double], y: [Double], order: Int, passThrough: (Double, Double)? = nil) throws -> FitResult {
        let pts = zip(x, y).filter { $0.0.isFinite && $0.1.isFinite }
        let n = Swift.max(0, Swift.min(order, 9))
        let needed = passThrough == nil ? n + 1 : Swift.max(n, 1)
        guard pts.count >= needed else { throw FitError.notEnoughPoints(needed: needed) }

        let xs = pts.map(\.0), ys = pts.map(\.1)
        let center: Double
        let scale: Double
        if let p = passThrough {
            center = p.0
        } else {
            center = xs.reduce(0, +) / Double(xs.count)
        }
        let spread = xs.map { Swift.abs($0 - center) }.max() ?? 1
        scale = spread > 0 ? spread : 1
        let ts = xs.map { ($0 - center) / scale }

        var scaled: [Double]
        if let p = passThrough {
            // y - y0 = Σ_{k=1..n} c_k t^k
            if n == 0 {
                scaled = [p.1]
            } else {
                let rhs = ys.map { $0 - p.1 }
                let design = ts.map { t in (1...n).map { Foundation.pow(t, Double($0)) } }
                let c = try leastSquares(design: design, rhs: rhs)
                scaled = [p.1] + c
            }
        } else {
            let design = ts.map { t in (0...n).map { Foundation.pow(t, Double($0)) } }
            scaled = try leastSquares(design: design, rhs: ys)
        }

        // t の多項式を x の多項式に直す(表示用)
        var coeffs = [Double](repeating: 0, count: scaled.count)
        for (k, ck) in scaled.enumerated() {
            // ck * ((x - center)/scale)^k
            let factor = ck / Foundation.pow(scale, Double(k))
            for j in 0...k {
                let binom = binomial(k, j)
                coeffs[j] += factor * binom * Foundation.pow(-center, Double(k - j))
            }
        }
        var result = FitResult(model: .polynomial(coefficients: coeffs, scaledCoefficients: scaled, center: center, scale: scale),
                               correlation: 0, chiSquare: 0, pointCount: pts.count)
        let fitted = xs.map { result.evaluate($0) }
        result.chiSquare = zip(fitted, ys).reduce(0) { $0 + ($1.0 - $1.1) * ($1.0 - $1.1) }
        result.correlation = correlation(fitted: fitted, observed: ys, linearX: n == 1 && passThrough == nil ? xs : nil)
        return result
    }

    static func binomial(_ n: Int, _ k: Int) -> Double {
        if k < 0 || k > n { return 0 }
        var r = 1.0
        for i in 0..<k { r = r * Double(n - i) / Double(i + 1) }
        return r
    }

    /// 相関係数。一次式は x と y の相関、それ以外は 1 - 残差/全変動 の平方根
    /// 相関係数 |r|: √(SSreg / (SSreg + SSres))。SSreg は当てはめた値のその平均からの二乗和、
    /// SSres は残差の二乗和。切片のある普通の最小二乗では 1 − SSres/SStot と同じで、点を通す当てはめや一般関数でも
    /// 1 次の多項式(linearX)は x と y の相関の符号を付ける
    static func correlation(fitted: [Double], observed: [Double], linearX: [Double]? = nil) -> Double {
        let n = Double(observed.count)
        guard n >= 2 else { return .nan }
        if let xs = linearX {
            let mx = xs.reduce(0, +) / n, my = observed.reduce(0, +) / n
            var sxy = 0.0, sxx = 0.0, syy = 0.0
            for (x, y) in zip(xs, observed) {
                sxy += (x - mx) * (y - my); sxx += (x - mx) * (x - mx); syy += (y - my) * (y - my)
            }
            return sxx > 0 && syy > 0 ? sxy / Foundation.sqrt(sxx * syy) : .nan
        }
        let mf = fitted.reduce(0, +) / n
        var ssReg = 0.0, ssRes = 0.0
        for (f, y) in zip(fitted, observed) {
            ssReg += (f - mf) * (f - mf)
            ssRes += (y - f) * (y - f)
        }
        guard ssReg + ssRes > 0 else { return 1 }
        return Foundation.sqrt(ssReg / (ssReg + ssRes))
    }

    /// 直線 y = a0 + a1 x の最小二乗(a0, a1, R)。through があれば、その点を通る直線(R は 1 − 残差/全変動 の平方根)
    static func linear(_ xs: [Double], _ ys: [Double], through: (Double, Double)? = nil) throws -> (Double, Double, Double) {
        if let (x0, y0) = through {
            // y − y0 = a1 (x − x0)
            guard !xs.isEmpty else { throw FitError.notEnoughPoints(needed: 1) }
            var sxy = 0.0, sxx = 0.0
            for (x, y) in zip(xs, ys) { sxy += (x - x0) * (y - y0); sxx += (x - x0) * (x - x0) }
            guard sxx > 0 else { throw FitError.singular }
            let a1 = sxy / sxx
            let fitted = xs.map { y0 + a1 * ($0 - x0) }
            return (y0 - a1 * x0, a1, correlation(fitted: fitted, observed: ys))
        }
        let n = Double(xs.count)
        guard xs.count >= 2 else { throw FitError.notEnoughPoints(needed: 2) }
        let mx = xs.reduce(0, +) / n, my = ys.reduce(0, +) / n
        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for (x, y) in zip(xs, ys) {
            sxy += (x - mx) * (y - my); sxx += (x - mx) * (x - mx); syy += (y - my) * (y - my)
        }
        guard sxx > 0 else { throw FitError.singular }
        let a1 = sxy / sxx
        let a0 = my - a1 * mx
        let r = syy > 0 ? sxy / Foundation.sqrt(sxx * syy) : 1
        return (a0, a1, r)
    }

    /// 通る点を、直線にした座標(ln x・ln y)に直す
    static func linearizedPoint(_ p: (Double, Double)?, logX: Bool, logY: Bool) throws -> (Double, Double)? {
        guard let (px, py) = p else { return nil }
        guard px.isFinite, py.isFinite, !logX || px > 0, !logY || py > 0 else { throw FitError.passThroughPointOutOfDomain }
        return (logX ? Foundation.log(px) : px, logY ? Foundation.log(py) : py)
    }

    /// 指数 ln y = a0 + a1 x(ln y の直線の最小二乗)。passThrough があれば、その点を通る(ln y の上で)
    public static func exponential(x: [Double], y: [Double], passThrough: (Double, Double)? = nil) throws -> FitResult {
        let pts = zip(x, y).filter { $0.0.isFinite && $0.1.isFinite && $0.1 > 0 }
        let through = try linearizedPoint(passThrough, logX: false, logY: true)
        let (a0, a1, r) = try linear(pts.map(\.0), pts.map { Foundation.log($0.1) }, through: through)
        var res = FitResult(model: .exponential(a0: a0, a1: a1), correlation: r, chiSquare: 0, pointCount: pts.count)
        res.chiSquare = pts.reduce(0) { let d = Foundation.log($1.1) - (a0 + a1 * $1.0); return $0 + d * d }
        return res
    }

    /// 対数 y = a0 + a1 ln x。passThrough があれば、その点を通る
    public static func logarithmic(x: [Double], y: [Double], passThrough: (Double, Double)? = nil) throws -> FitResult {
        let pts = zip(x, y).filter { $0.0.isFinite && $0.1.isFinite && $0.0 > 0 }
        let through = try linearizedPoint(passThrough, logX: true, logY: false)
        let (a0, a1, r) = try linear(pts.map { Foundation.log($0.0) }, pts.map(\.1), through: through)
        var res = FitResult(model: .logarithmic(a0: a0, a1: a1), correlation: r, chiSquare: 0, pointCount: pts.count)
        res.chiSquare = pts.reduce(0) { let d = $1.1 - (a0 + a1 * Foundation.log($1.0)); return $0 + d * d }
        return res
    }

    /// べき乗 ln y = a0 + a1 ln x(両対数の直線の最小二乗)。passThrough があれば、その点を通る(両対数の上で)
    public static func power(x: [Double], y: [Double], passThrough: (Double, Double)? = nil) throws -> FitResult {
        let pts = zip(x, y).filter { $0.0.isFinite && $0.1.isFinite && $0.0 > 0 && $0.1 > 0 }
        let through = try linearizedPoint(passThrough, logX: true, logY: true)
        let (a0, a1, r) = try linear(pts.map { Foundation.log($0.0) }, pts.map { Foundation.log($0.1) }, through: through)
        var res = FitResult(model: .power(a0: a0, a1: a1), correlation: r, chiSquare: 0, pointCount: pts.count)
        res.chiSquare = pts.reduce(0) { let d = Foundation.log($1.1) - (a0 + a1 * Foundation.log($1.0)); return $0 + d * d }
        return res
    }

    /// 一般関数の当てはめのパラメータ(a〜i の 9 個)
    public static let parameterNames = ["a", "b", "c", "d", "e", "f", "g", "h", "i"]

    /// 偏微分を差分で近似するときの刻み(パラメータの値に対する比)。中心差分の誤差が最小になる ε^(1/3)
    static let differenceStep = Foundation.cbrt(Double.ulpOfOne)

    /// 一般関数のフィット(Marquardt 法)。derivatives は ∂f/∂a … ∂f/∂g の式(空なら差分で近似)。
    /// fixed のパラメータは動かさず、initial の値(無ければ 1)の定数として使う。
    /// tolerancePercent > 0 なら、いまの点から二乗和の最小までの残り(減衰なしのガウス・ニュートンの一歩で見積もる)が
    /// 2 回続けて、動かすパラメータのどれでもその値のその % 以下になったら、その一歩を加えて止める(0 なら止めない)。
    /// 減衰の大きい小さな一歩は最小から遠くでも起きるので、実際に動いた一歩の大きさでは止めない。
    public static func general(x: [Double], y: [Double], function: String, derivatives: [String] = [],
                               initial: [String: Double] = [:], constants: [String: Double] = [:],
                               maxIterations: Int = 300, fixed: Set<String> = [], tolerancePercent: Double = 0) throws -> FitResult {
        let expr: Expression
        do { expr = try Expression(function) } catch { throw FitError.badExpression((error as? ExpressionError)?.message ?? "\(error)") }
        let used = expr.referencedVariables()
        let usedParams = parameterNames.filter { used.contains($0) }
        guard !usedParams.isEmpty else { throw FitError.badExpression("パラメータ a〜i が式に含まれていません。") }
        let params = usedParams.filter { !fixed.contains($0) }
        let pts = zip(x, y).filter { $0.0.isFinite && $0.1.isFinite }
        let needed = Swift.max(params.count, 1)
        guard pts.count >= needed else { throw FitError.notEnoughPoints(needed: needed) }
        let xs = pts.map(\.0), ys = pts.map(\.1)

        var derivExprs: [Expression?] = []
        for (i, name) in parameterNames.enumerated() where params.contains(name) {
            let s = i < derivatives.count ? derivatives[i].trimmingCharacters(in: .whitespaces) : ""
            derivExprs.append(s.isEmpty ? nil : try? Expression(s))
        }

        var base = constants
        // 当てはめないパラメータは初期値のまま(初期値の行に無ければ 0)
        for name in usedParams where fixed.contains(name) { base[name] = initial[name] ?? 0 }
        let tolerance = tolerancePercent.isFinite && tolerancePercent > 0 ? tolerancePercent / 100 : 0
        var p = params.map { initial[$0] ?? 0 }

        func values(_ p: [Double]) -> [Double] {
            var c = base
            for (i, n) in params.enumerated() { c[n] = p[i] }
            let ctx = ExprContext(count: xs.count, x: xs, y: ys, constants: c)
            return (try? expr.evaluate(ctx)) ?? xs.map { _ in .nan }
        }
        func chi(_ v: [Double]) -> Double {
            var s = 0.0
            for (a, b) in zip(v, ys) { let d = a - b; s += d * d }
            return s
        }
        func jacobian(_ p: [Double], _ f0: [Double]) -> [[Double]] {
            var cols: [[Double]] = []
            var c = base
            for (i, n) in params.enumerated() { c[n] = p[i] }
            for (j, _) in params.enumerated() {
                if let de = derivExprs[j], let v = try? de.evaluate(ExprContext(count: xs.count, x: xs, y: ys, constants: c)) {
                    cols.append(v)
                } else {
                    // 中心差分。刻みはパラメータの大きさに比例させる(単位によらない)。片側しか計算できない点は片側の差分
                    let step = p[j] != 0 ? Swift.abs(p[j]) * Fitting.differenceStep : Fitting.differenceStep
                    var qp = p, qm = p
                    qp[j] += step; qm[j] -= step
                    let hp = qp[j] - p[j], hm = p[j] - qm[j]
                    let fp = values(qp), fm = values(qm)
                    cols.append((0..<xs.count).map { i in
                        if fp[i].isFinite && fm[i].isFinite { return (fp[i] - fm[i]) / (hp + hm) }
                        if fp[i].isFinite { return (fp[i] - f0[i]) / hp }
                        if fm[i].isFinite { return (f0[i] - fm[i]) / hm }
                        return .nan
                    })
                }
            }
            // 行 = 点、列 = パラメータ
            return (0..<xs.count).map { i in cols.map { $0[i] } }
        }

        var f0 = values(p)
        var current = chi(f0)
        guard current.isFinite else { throw FitError.didNotConverge }

        // 許容誤差があるとき(ファイルの系列はいつもある): Marquardt 法。
        // λ は 0.01 から、二乗和が減れば 1/10、減らなければ 10 倍。減らした一歩の二乗和の減り方が許容誤差(%)以下で止める。
        // 偏微分の式が無いパラメータは前進差分(刻みは値の 1/1000)
        if tolerance > 0 && !params.isEmpty {
            func jacobianForward(_ p: [Double], _ f0: [Double]) -> [[Double]] {
                var c = base
                for (i, n) in params.enumerated() { c[n] = p[i] }
                var cols: [[Double]] = []
                for j in params.indices {
                    if let de = derivExprs[j], let v = try? de.evaluate(ExprContext(count: xs.count, x: xs, y: ys, constants: c)) {
                        cols.append(v)
                    } else {
                        let step = p[j] != 0 ? Swift.abs(p[j]) * 1e-3 : 1e-3
                        var q = p
                        q[j] += step
                        let fq = values(q)
                        cols.append((0..<xs.count).map { (fq[$0] - f0[$0]) / step })
                    }
                }
                return (0..<xs.count).map { i in cols.map { $0[i] } }
            }
            var lambda = 0.01
            let m = params.count
            var done = false
            for _ in 0..<(maxIterations * 20) {
                let J = jacobianForward(p, f0)
                var A = [[Double]](repeating: [Double](repeating: 0, count: m), count: m)
                var g = [Double](repeating: 0, count: m)
                for (i, row) in J.enumerated() {
                    let r = ys[i] - f0[i]
                    for a in 0..<m {
                        g[a] += row[a] * r
                        for b in 0..<m { A[a][b] += row[a] * row[b] }
                    }
                }
                for a in 0..<m { A[a][a] *= (1 + lambda) }
                if let d = solve(A, g) {
                    let q = zip(p, d).map { $0 + $1 }
                    let f1 = values(q)
                    let c1 = chi(f1)
                    if c1.isFinite && c1 < current {
                        let decrease = c1 > 0 ? (current - c1) / c1 : 0
                        p = q; f0 = f1; current = c1
                        lambda *= 0.1
                        if decrease <= tolerance { done = true; break }
                        continue
                    }
                }
                lambda *= 10
                if lambda > 1e30 { done = true; break }   // これ以上減らせない(最小にいる)
            }
            guard done else { throw FitError.didNotConverge }
            var dict: [String: Double] = base
            for (i, n) in params.enumerated() { dict[n] = p[i] }
            return FitResult(model: .general(expression: function, parameters: dict),
                             correlation: correlation(fitted: f0, observed: ys), chiSquare: current, pointCount: xs.count)
        }

        var lambda = 1e-3
        var converged = params.isEmpty   // 全部固定なら計算するだけ
        var smallRemainders = 0
        for _ in 0..<(params.isEmpty ? 0 : maxIterations) {
            let J = jacobian(p, f0)
            let m = params.count
            var JTJ = [[Double]](repeating: [Double](repeating: 0, count: m), count: m)
            var JTr = [Double](repeating: 0, count: m)
            for (i, row) in J.enumerated() {
                let r = ys[i] - f0[i]
                for a in 0..<m {
                    JTr[a] += row[a] * r
                    for b in 0..<m { JTJ[a][b] += row[a] * row[b] }
                }
            }
            // 許容誤差: 最小までの残りが 2 回続けて各パラメータの値の tolerance 以下なら、その一歩を加えて止める
            if tolerance > 0 {
                if let gn = solve(JTJ, JTr), zip(gn, p).allSatisfy({ d, v in Swift.abs(d) <= tolerance * Swift.abs(v) }) {
                    smallRemainders += 1
                    if smallRemainders >= 2 {
                        let q = zip(p, gn).map { $0 + $1 }
                        let f1 = values(q)
                        let c1 = chi(f1)
                        if c1.isFinite && c1 <= current { p = q; f0 = f1; current = c1 }
                        converged = true
                        break
                    }
                } else {
                    smallRemainders = 0
                }
            }
            var improved = false
            for _ in 0..<20 {
                var A = JTJ
                for a in 0..<m { A[a][a] *= (1 + lambda); if A[a][a] == 0 { A[a][a] = lambda } }
                guard let delta = solve(A, JTr) else { lambda *= 10; continue }
                let q = zip(p, delta).map { $0 + $1 }
                let f1 = values(q)
                let c1 = chi(f1)
                if c1.isFinite && c1 <= current {
                    let rel = (current - c1) / Swift.max(current, 1e-300)
                    p = q; f0 = f1
                    current = c1
                    lambda = Swift.max(lambda / 10, 1e-12)
                    improved = true
                    // 二乗和がほとんど減らない、または各パラメータの変化がその値に比べて十分小さい(単位によらない比で見る)
                    if rel < 1e-12 || zip(delta, q).allSatisfy({ d, v in Swift.abs(d) <= 1e-12 * Swift.abs(v) }) { converged = true }
                    break
                }
                lambda *= 10
            }
            if !improved || converged { converged = true; break }
        }
        guard converged || current.isFinite else { throw FitError.didNotConverge }
        var dict: [String: Double] = [:]
        for (i, n) in params.enumerated() { dict[n] = p[i] }
        var allConstants = base
        for (k, v) in dict { allConstants[k] = v }
        let r = correlation(fitted: f0, observed: ys)
        // 評価用の式には定数も入れて持つ
        return FitResult(model: .general(expression: function, parameters: allConstants), correlation: r,
                         chiSquare: current, pointCount: xs.count)
    }

    // MARK: - 線形代数

    /// 最小二乗解(Householder QR。列はスケール済みで条件は良い)
    static func leastSquares(design: [[Double]], rhs: [Double]) throws -> [Double] {
        guard let m = design.first?.count, m > 0 else { throw FitError.singular }
        // Householder QR
        var A = design
        var b = rhs
        let rows = A.count
        guard rows >= m else { throw FitError.notEnoughPoints(needed: m) }
        // 階数落ちの判定の大きさ: 点の数 × ε × いちばん長い列の長さ(LAPACK・numpy の lstsq と同じ考え方)。
        // 違う x の数が次数 + 1 に足りないとき、R の対角は丸めの大きさになり、点が多いほど大きくなるので比で見る
        var longest = 0.0
        for j in 0..<m {
            var s = 0.0
            for i in 0..<rows { s += A[i][j] * A[i][j] }
            longest = Swift.max(longest, Foundation.sqrt(s))
        }
        let rankTolerance = Double(Swift.max(rows, m)) * Double.ulpOfOne * longest
        for k in 0..<m {
            var norm = 0.0
            for i in k..<rows { norm += A[i][k] * A[i][k] }
            norm = Foundation.sqrt(norm)
            if norm == 0 { throw FitError.singular }
            let alpha = A[k][k] > 0 ? -norm : norm
            var v = [Double](repeating: 0, count: rows)
            for i in k..<rows { v[i] = A[i][k] }
            v[k] -= alpha
            var vnorm = 0.0
            for i in k..<rows { vnorm += v[i] * v[i] }
            if vnorm == 0 { continue }
            for j in k..<m {
                var s = 0.0
                for i in k..<rows { s += v[i] * A[i][j] }
                let f = 2 * s / vnorm
                for i in k..<rows { A[i][j] -= f * v[i] }
            }
            var s = 0.0
            for i in k..<rows { s += v[i] * b[i] }
            let f = 2 * s / vnorm
            for i in k..<rows { b[i] -= f * v[i] }
        }
        var x = [Double](repeating: 0, count: m)
        for i in stride(from: m - 1, through: 0, by: -1) {
            var s = b[i]
            for j in (i + 1)..<m { s -= A[i][j] * x[j] }
            if !(Swift.abs(A[i][i]) > rankTolerance) { throw FitError.singular }
            x[i] = s / A[i][i]
        }
        return x
    }

    /// Marquardt 法の結果
    struct MarquardtResult {
        var parameters: [Double]
        var chiSquare: Double
        var iterations: Int
    }

    /// Levenberg–Marquardt 法(パラメータの一部を固定できる)。
    /// model(p, x) が値、gradient(p, x) が各パラメータでの偏微分(p と同じ数)。
    /// 二乗和の相対変化が precision より小さくなる(2 回続けて)か、maxIterations 回で止める。
    static func marquardt(x: [Double], y: [Double], initial: [Double], vary: [Bool],
                          precision: Double, maxIterations: Int = 200,
                          model: ([Double], Double) -> Double,
                          gradient: ([Double], Double) -> [Double]) throws -> MarquardtResult {
        let free = initial.indices.filter { $0 < vary.count && vary[$0] }
        var p = initial
        func chi(_ q: [Double]) -> Double {
            var s = 0.0
            for i in x.indices { let d = y[i] - model(q, x[i]); s += d * d }
            return s
        }
        var current = chi(p)
        guard current.isFinite else { throw FitError.didNotConverge }
        if free.isEmpty || current == 0 { return MarquardtResult(parameters: p, chiSquare: current, iterations: 0) }
        guard x.count >= free.count else { throw FitError.notEnoughPoints(needed: free.count) }

        let tol = precision.isFinite && precision > 0 ? precision : 1e-6
        let m = free.count
        var lambda = 1e-3
        var iterations = 0
        var smallSteps = 0
        while iterations < maxIterations {
            iterations += 1
            var JTJ = [[Double]](repeating: [Double](repeating: 0, count: m), count: m)
            var JTr = [Double](repeating: 0, count: m)
            for i in x.indices {
                let g = gradient(p, x[i])
                let r = y[i] - model(p, x[i])
                for a in 0..<m {
                    let ga = g[free[a]]
                    JTr[a] += ga * r
                    for b in 0...a { JTJ[a][b] += ga * g[free[b]] }
                }
            }
            for a in 0..<m { for b in 0..<a { JTJ[b][a] = JTJ[a][b] } }
            guard JTJ.allSatisfy({ $0.allSatisfy(\.isFinite) }), JTr.allSatisfy(\.isFinite) else { break }

            var accepted = false
            var next = current
            while lambda < 1e16 {
                var A = JTJ
                for a in 0..<m { A[a][a] = JTJ[a][a] == 0 ? lambda : JTJ[a][a] * (1 + lambda) }
                if let delta = solve(A, JTr) {
                    var q = p
                    for a in 0..<m { q[free[a]] += delta[a] }
                    let c = chi(q)
                    if c.isFinite && c <= current {
                        p = q; next = c; accepted = true
                        lambda = Swift.max(lambda / 10, 1e-15)
                        break
                    }
                }
                lambda *= 10
            }
            // どちらへ動かしても小さくならない = 極小に着いた
            if !accepted { break }
            let rel = (current - next) / Swift.max(current, 1e-300)
            current = next
            if current == 0 { break }
            if rel < tol {
                smallSteps += 1
                if smallSteps >= 2 { break }
            } else {
                smallSteps = 0
            }
        }
        guard current.isFinite, p.allSatisfy(\.isFinite) else { throw FitError.didNotConverge }
        return MarquardtResult(parameters: p, chiSquare: current, iterations: iterations)
    }

    static func solve(_ A: [[Double]], _ b: [Double]) -> [Double]? {
        let n = b.count
        var M = A
        var v = b
        for c in 0..<n {
            var piv = c
            for r in (c + 1)..<n where Swift.abs(M[r][c]) > Swift.abs(M[piv][c]) { piv = r }
            if Swift.abs(M[piv][c]) < 1e-300 { return nil }
            M.swapAt(c, piv); v.swapAt(c, piv)
            for r in (c + 1)..<n {
                let f = M[r][c] / M[c][c]
                if f == 0 { continue }
                for k in c..<n { M[r][k] -= f * M[c][k] }
                v[r] -= f * v[c]
            }
        }
        var x = [Double](repeating: 0, count: n)
        for i in stride(from: n - 1, through: 0, by: -1) {
            var s = v[i]
            for j in (i + 1)..<n { s -= M[i][j] * x[j] }
            x[i] = s / M[i][i]
        }
        return x.allSatisfy({ $0.isFinite }) ? x : nil
    }
}
