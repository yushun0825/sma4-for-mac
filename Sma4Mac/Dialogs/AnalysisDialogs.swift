import AppKit
import Sma4Core

/// 解析メニューのダイアログ(最小二乗の条件・描画条件・定数の設定・最小二乗の結果・Fitting Cond.)
@MainActor
enum AnalysisDialogs {

    // MARK: - 最小二乗の条件(適用条件・関数定義・描画条件)

    static func leastSquares(series s0: Series, over window: NSWindow?) -> Series? {
        var pages: [(String, DlgTemplate)] = []
        switch s0.kind {
        case .polynomialLSQ: pages.append(("当てはめ", .lsqOrder))
        case .generalLSQ: pages.append(("関数", .generalFunction))
        default: break
        }
        pages.append(("描き方", .lsqDraw))
        let title = s0.kind == .spline || s0.kind == .function ? "描き方" : "最小二乗の条件"
        let sheet = PropertySheet(title: title, pages: pages)
        let curve = sheet.pages.last!
        for p in sheet.pages { p.setLabel(731, DataDialogs.displayPath(s0)) }
        CurvePage.fill(curve, s0)
        curve.on(557) {
            CurvePage.saveDefaults(curve)
            MessageBox.show("描画条件を既定にしました。")
        }
        var readFirst: ((inout Series) -> Void)?
        var validateFirst: (() -> Bool)?
        if s0.kind == .polynomialLSQ {
            let p = sheet.page(0)
            p.setItems(671, (0...9).map(String.init))
            p.select(671, max(0, min(s0.lsqOrder, 9)))
            p.setChecked(672, s0.passThroughPoint)
            p.setNumber(673, s0.passX)
            p.setNumber(674, s0.passY)
            let upd = { p.setEnabled(673, p.isChecked(672)); p.setEnabled(674, p.isChecked(672)) }
            p.on(672, upd)
            upd()
            p.on(557) {
                AppSettings.shared.store(max(p.selectedIndex(671), 0), key: "lsq.dimension")
                MessageBox.show("次数を既定にしました。")
            }
            readFirst = { s in
                s.lsqOrder = max(p.selectedIndex(671), 0)
                s.passThroughPoint = p.isChecked(672)
                s.passX = p.number(673, or: s.passX)
                s.passY = p.number(674, or: s.passY)
            }
        } else if s0.kind == .generalLSQ {
            let p = sheet.page(0)
            let fn = GeneralFunctionPage(p, series: s0)
            readFirst = { s in fn.read(into: &s) }
            validateFirst = { fn.validate() }
        }
        sheet.validate = {
            if let v = validateFirst, !v() { return false }
            if curve.number(513) == nil || curve.number(514) == nil { MessageBox.show("From・To に数を入れてください。"); return false }
            return true
        }
        guard sheet.run(over: window) == IDC.ok else { return nil }
        var s = s0
        readFirst?(&s)
        CurvePage.read(curve, into: &s)
        return s
    }

    // MARK: - 定数の設定

    static func constants(_ values: [Double], over window: NSWindow?, apply: @escaping ([Double]) -> Void) -> [Double]? {
        let dlg = Dialog(.constants)
        let p = dlg.page
        let ids = Array(787...795)
        for (k, id) in ids.enumerated() { p.setNumber(id, k < values.count ? values[k] : 0, format: "%.10g") }
        func read() -> [Double] { ids.enumerated().map { k, id in p.number(id, or: k < values.count ? values[k] : 0) } }
        dlg.buttons[917] = {  // Copy
            let text = zip(["a", "b", "c", "d", "e", "f", "g", "h", "i"], read()).map { "\($0)=\(String(format: "%.10le", $1))" }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text.joined(separator: "\r\n"), forType: .string)
            return false
        }
        dlg.buttons[918] = {  // Paste: "a=1.0" の形か、数を並べたもの
            guard let s = NSPasteboard.general.string(forType: .string) else { return false }
            var vals = read()
            var k = 0
            for token in s.components(separatedBy: CharacterSet(charactersIn: " \t\r\n,")) where !token.isEmpty {
                var t = token
                if let eq = t.firstIndex(of: "=") {
                    let name = t[..<eq].trimmingCharacters(in: .whitespaces)
                    if let idx = ["a", "b", "c", "d", "e", "f", "g", "h", "i"].firstIndex(of: name) { k = idx }
                    t = String(t[t.index(after: eq)...])
                }
                if let v = Double(t), k < 9 { vals[k] = v; k += 1 }
            }
            for (j, id) in ids.enumerated() { p.setNumber(id, vals[j], format: "%.10g") }
            return false
        }
        dlg.buttons[919] = {  // Apply
            apply(read())
            return false
        }
        guard dlg.run(over: window) == IDC.ok else { return nil }
        return read()
    }

    // MARK: - 最小二乗の結果

    enum InfoResult { case close, new }

    static func information(title: String, lines: [String], over window: NSWindow?) -> InfoResult {
        let dlg = Dialog(.lsqResult, title: "最小二乗の結果")
        let p = dlg.page
        p.setLabel(731, title)
        p.list(732)?.items = lines
        dlg.buttons[7] = {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(lines.joined(separator: "\r\n"), forType: .string)
            return false
        }
        dlg.buttons[797] = { true }
        return dlg.run(over: window) == 797 ? .new : .close
    }

    // MARK: - Fitting Cond.(Gaussian・Lorenzian fitting)

    static func fittingCondition(_ f0: PeakFitSettings, over window: NSWindow?) -> PeakFitSettings? {
        let dlg = Dialog(.fittingStart)
        let p = dlg.page
        var f = f0
        var bank = 0  // 0: 1〜3、1: 4〜6
        p.setItems(2023, (1...PeakFitSettings.maxPeaks).map(String.init))
        p.select(2023, max(0, min(f.count, PeakFitSettings.maxPeaks) - 1))
        p.setNumber(2024, f.precision)
        p.setChecked(2010, f.varyOffset)
        p.setNumber(2020, f.offset)
        func store() {
            for k in 0..<3 {
                let i = bank * 3 + k
                f.varyIntensity[i] = p.isChecked(2001 + k * 3)
                f.varyPosition[i] = p.isChecked(2002 + k * 3)
                f.varyWidth[i] = p.isChecked(2003 + k * 3)
                f.intensity[i] = p.number(2011 + k * 3, or: f.intensity[i])
                f.position[i] = p.number(2012 + k * 3, or: f.position[i])
                f.width[i] = p.number(2013 + k * 3, or: f.width[i])
            }
        }
        func load() {
            let count = max(p.selectedIndex(2023), 0) + 1
            for k in 0..<3 {
                let i = bank * 3 + k
                p.setText(2001 + k * 3, "\(i + 1) の強さ")
                p.setText(2002 + k * 3, "\(i + 1) の位置")
                p.setText(2003 + k * 3, "\(i + 1) の半値幅")
                p.setChecked(2001 + k * 3, f.varyIntensity[i])
                p.setChecked(2002 + k * 3, f.varyPosition[i])
                p.setChecked(2003 + k * 3, f.varyWidth[i])
                p.setNumber(2011 + k * 3, f.intensity[i])
                p.setNumber(2012 + k * 3, f.position[i])
                p.setNumber(2013 + k * 3, f.width[i])
                let on = i < count
                for id in [2001 + k * 3, 2002 + k * 3, 2003 + k * 3, 2011 + k * 3, 2012 + k * 3, 2013 + k * 3] { p.setEnabled(id, on) }
            }
            p.setEnabled(2022, count > 3)
        }
        p.on(2023) { store(); load() }
        dlg.buttons[2021] = { store(); bank = 0; load(); return false }
        dlg.buttons[2022] = { store(); bank = 1; load(); return false }
        load()
        guard dlg.run(over: window) == IDC.ok else { return nil }
        store()
        f.count = max(p.selectedIndex(2023), 0) + 1
        f.precision = max(p.number(2024, or: f.precision), 1e-12)
        f.varyOffset = p.isChecked(2010)
        f.offset = p.number(2020, or: f.offset)
        return f
    }
}

/// 関数定義(一般関数の最小二乗)のページ
@MainActor
final class GeneralFunctionPage {
    let p: TemplateView
    static let names = ["a", "b", "c", "d", "e", "f", "g", "h", "i"]
    /// 保存した関数(10 個まで)
    struct Entry: Codable { var function: String; var derivatives: [String]; var initial: [Double]; var vary: [Bool]; var tolerance: Double }
    var history: [Entry]

    init(_ p: TemplateView, series s: Series) {
        self.p = p
        history = AppSettings.shared.stored("lsq.functions", as: [Entry].self) ?? []
        let initial = SeriesEvaluator.initialParameters(s.generalParameterLine)
        let current = Entry(function: s.generalFunction.isEmpty ? (history.first?.function ?? "a*exp(b*x)") : s.generalFunction,
                            derivatives: s.generalDerivatives,
                            initial: GeneralFunctionPage.names.map { initial[$0] ?? 1 },
                            vary: GeneralFunctionPage.names.map { name in !s.generalFixed.contains(name) },
                            tolerance: s.generalTolerance)
        fill(current)
        if let sl = p.slider(820) {
            sl.minValue = 0
            sl.maxValue = Double(max(history.count, 1))
            sl.numberOfTickMarks = max(history.count + 1, 2)
            sl.allowsTickMarkValuesOnly = true
            sl.doubleValue = 0
        }
        p.on(820) { [weak self] in
            guard let self, let sl = self.p.slider(820) else { return }
            let k = Int(sl.doubleValue.rounded())
            if k == 0 { self.fill(current) } else if k - 1 < self.history.count { self.fill(self.history[k - 1]) }
        }
        p.on(557) { [weak self] in
            guard let self else { return }
            var s = Series(name: "")
            self.read(into: &s)
            let e = Entry(function: s.generalFunction, derivatives: s.generalDerivatives,
                          initial: GeneralFunctionPage.names.map { SeriesEvaluator.initialParameters(s.generalParameterLine)[$0] ?? 1 },
                          vary: GeneralFunctionPage.names.map { !s.generalFixed.contains($0) }, tolerance: s.generalTolerance)
            self.history.removeAll { $0.function == e.function }
            self.history.insert(e, at: 0)
            self.history = Array(self.history.prefix(10))
            AppSettings.shared.store(self.history, key: "lsq.functions")
            MessageBox.show("関数を保存しました(スクロールバーで呼び出せます)。")
        }
        for (k, _) in GeneralFunctionPage.names.enumerated() {
            p.on(811 + k) { [weak self] in self?.updateEnabled() }
        }
    }

    func fill(_ e: Entry) {
        p.setText(777, e.function)
        for k in 0..<9 {
            p.setChecked(811 + k, k < e.vary.count ? e.vary[k] : true)
            p.setNumber(787 + k, k < e.initial.count ? e.initial[k] : 1)
            p.setText(778 + k, k < e.derivatives.count ? e.derivatives[k] : "")
        }
        p.setNumber(796, e.tolerance)
        updateEnabled()
    }

    func updateEnabled() {
        // a〜g の 7 つまで
        for k in 7..<9 {
            for id in [811 + k, 787 + k, 778 + k] { p.setEnabled(id, false) }
        }
    }

    func read(into s: inout Series) {
        s.generalFunction = p.text(777).trimmingCharacters(in: .whitespaces)
        s.generalDerivatives = (0..<7).map { p.text(778 + $0).trimmingCharacters(in: .whitespaces) }
        let values = (0..<7).map { p.number(787 + $0, or: 1) }
        s.generalParameterLine = "7 " + values.map { String(format: "%.10g", $0) }.joined(separator: " ") + " 0"
        s.generalFixed = Set((0..<7).filter { !p.isChecked(811 + $0) }.map { GeneralFunctionPage.names[$0] })
        s.generalTolerance = max(p.number(796, or: 0.001), 0)
    }

    func validate() -> Bool {
        let f = p.text(777).trimmingCharacters(in: .whitespaces)
        do { _ = try Expression(f) } catch {
            MessageBox.show("f(x) の式が正しくありません。\n\((error as? ExpressionError)?.message ?? "")", style: .warning)
            return false
        }
        return true
    }
}
