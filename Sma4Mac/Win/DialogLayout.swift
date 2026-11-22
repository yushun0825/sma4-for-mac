import Foundation
import CoreText

/// ダイアログの配置を組み立てる(位置と大きさは DLU)。行を上から積んで DlgTemplate にする。
/// 決まり:
/// - 欄の見出しは右寄せで「：」を付け、見出しの列の幅をそろえて欄の左端を合わせる
/// - チェックボックス・ラジオボタンは見出しを付けずに並べる
/// - いちばん下の押しボタンは右寄せで、OK がいちばん右。消去などはその左、位置の指定などは左端
struct DlgLayout {
    enum Align { case left, center, right }

    /// 行の中の部品 1 つ
    enum Cell {
        case text(String, w: Int? = nil, id: Int = IDC.static, align: Align = .left)
        case field(Int, w: Int, readOnly: Bool = false, disabled: Bool = false)
        case check(Int, String, w: Int? = nil, disabled: Bool = false)
        /// first はラジオボタンのまとまりの始まり。manual は 1 つずつ別に入り切りするもの
        case radio(Int, String, w: Int? = nil, first: Bool = false, manual: Bool = false)
        case popup(Int, w: Int, owner: Bool = false)
        case combo(Int, w: Int)
        case color(Int)
        case push(Int, String, w: Int? = nil)
        case gap(Int)
    }

    // 寸法の決まり(DLU。1 DLU = 横 1.75 点・縦 1.5 点)
    static let margin = 10
    static let top = 8
    static let gap = 4
    static let fieldH = 12
    static let fieldPitch = 18
    static let togglePitch = 13
    static let buttonW = 44
    static let buttonH = 14

    private(set) var items: [DlgItem] = []
    let x0: Int
    let x1: Int
    var y: Int
    /// 見出しの列の幅(row の見出し)
    var labelW: Int

    var width: Int { x1 - x0 }

    init(x0: Int, x1: Int, y: Int, labelW: Int = 0) {
        self.x0 = x0; self.x1 = x1; self.y = y; self.labelW = labelW
    }

    /// 1 枚のダイアログ(タブの 1 ページも同じ)
    static func dialog(_ title: String = "", width: Int, _ body: (inout DlgLayout) -> Void) -> DlgTemplate {
        var d = DlgLayout(x0: margin, x1: width - margin, y: top)
        body(&d)
        return DlgTemplate(name: "", title: title, cx: width, cy: d.y + 2, style: 0, items: d.items)
    }

    // MARK: - 見出しの列

    /// 見出しの列の幅を、いちばん長い見出しに合わせる
    mutating func labels(_ list: String...) {
        labelW = list.map { DlgMeasure.dlu(Self.labelText($0), extra: 3) }.max() ?? 0
    }

    private static func labelText(_ s: String) -> String { s.isEmpty || s.hasSuffix("：") ? s : s + "：" }

    // MARK: - 行

    /// 見出し(nil なら見出しの列を使わない。"" なら列の幅だけ空ける)と部品を 1 行に並べる
    mutating func row(_ label: String? = nil, _ cells: Cell...) { row(label, cells) }

    mutating func row(_ label: String?, _ cells: [Cell]) {
        let tall = cells.contains { c in
            switch c {
            case .text, .check, .radio, .gap: return false
            default: return true
            }
        }
        var x = x0
        if let label {
            if !label.isEmpty {
                add(.label, IDC.static, x0, y + (tall ? 2 : 0), labelW, 10, S.base | 2, Self.labelText(label))
            }
            x = x0 + labelW + Self.gap
        }
        for c in cells {
            let w = width(of: c)
            place(c, x: x, w: w, tall: tall)
            x += w + Self.gap
        }
        y += tall ? Self.fieldPitch : Self.togglePitch
    }

    /// 欄の上に付ける列の見出し(見出しの列のぶん右から)
    mutating func columnTitles(_ titles: [(String, Int)]) {
        var x = x0 + (labelW > 0 ? labelW + Self.gap : 0)
        for (t, w) in titles {
            if !t.isEmpty { add(.label, IDC.static, x, y, w, 10, S.base | 1, t) }
            x += w + Self.gap
        }
        y += 11
    }

    /// チェックボックスを columns 列で並べる
    mutating func checks(_ list: [(Int, String)], columns: Int = 1, indent: Int = 0) {
        let cw = (width - indent) / max(columns, 1)
        for (k, (id, t)) in list.enumerated() {
            let c = k % columns
            add(.button, id, x0 + indent + c * cw, y, cw - Self.gap, 10, S.base | S.tab | 3, t)
            if c == columns - 1 || k == list.count - 1 { y += Self.togglePitch }
        }
    }

    /// ラジオボタンのまとまりを columns 列で並べる
    mutating func radios(_ list: [(Int, String)], columns: Int, indent: Int = 0) {
        let cw = (width - indent) / max(columns, 1)
        for (k, (id, t)) in list.enumerated() {
            let c = k % columns
            add(.button, id, x0 + indent + c * cw, y, cw - Self.gap, 10, S.base | 9 | (k == 0 ? S.group | S.tab : 0), t)
            if c == columns - 1 || k == list.count - 1 { y += Self.togglePitch }
        }
    }

    // MARK: - まとまり

    /// 題の付いた枠で囲む
    mutating func group(_ title: String, id: Int = IDC.static, labelW lw: Int? = nil, _ body: (inout DlgLayout) -> Void) {
        let at = items.count
        var inner = DlgLayout(x0: x0 + 7, x1: x1 - 7, y: y + 13, labelW: lw ?? labelW)
        body(&inner)
        let h = inner.y - y + 3
        items.insert(DlgItem(.button, id, x0, y, width, h, S.base | 7, title), at: at)
        items += inner.items
        y += h + 6
    }

    /// 左右に分けて並べる(ratio は左の幅の割合)
    mutating func split(_ ratio: Double = 0.5, gap g: Int = 8, _ left: (inout DlgLayout) -> Void, _ right: (inout DlgLayout) -> Void) {
        let mid = x0 + Int(Double(width - g) * ratio)
        var l = DlgLayout(x0: x0, x1: mid, y: y, labelW: labelW)
        var r = DlgLayout(x0: mid + g, x1: x1, y: y, labelW: labelW)
        left(&l)
        right(&r)
        items += l.items + r.items
        y = max(l.y, r.y)
    }

    // MARK: - 1 行を占める部品

    /// 幅いっぱいの 1 行の文字(id があれば処理の側で書き換える)
    mutating func note(_ text: String, id: Int = IDC.static, align: Align = .left) {
        add(.label, id, x0, y, width, 10, S.base | Self.alignBits(align), text)
        y += 13
    }

    mutating func list(_ id: Int, h: Int, multi: Bool = false, owner: Bool = false) {
        add(.listBox, id, x0, y, width, h, S.base | S.tab | S.vscroll | 1 | (multi ? 8 : 0) | (owner ? 0x10 : 0))
        y += h + 6
    }

    mutating func textArea(_ id: Int, h: Int, readOnly: Bool = false) {
        add(.edit, id, x0, y, width, h, S.base | S.tab | S.vscroll | 0x1004 | (readOnly ? 0x800 : 0))
        y += h + 6
    }

    /// 見本を描く枠
    mutating func sample(_ id: Int, w: Int, h: Int) {
        add(.button, id, x0, y, w, h, S.base | S.disabled | 0xB)
        y += h + 6
    }

    mutating func slider(_ id: Int, indent: Int = 0) {
        add(.scrollBar, id, x0 + indent, y, width - indent, 8, S.base | S.tab)
        y += 12
    }

    /// アプリのアイコン(真ん中)
    mutating func icon() {
        add(.label, IDC.static, x0 + width / 2 - 10, y, 20, 21, S.base | 3)
        y += 26
    }

    mutating func space(_ n: Int) { y += n }

    /// いちばん下の押しボタン。left は左から、right は右寄せ(OK を最後に書く)
    mutating func buttons(left: [(Int, String)] = [], right: [(Int, String)]) {
        y += 4
        var x = x0
        for (id, t) in left {
            let w = max(Self.buttonW, DlgMeasure.dlu(t, extra: 30))
            add(.button, id, x, y, w, Self.buttonH, S.base | S.tab, t)
            x += w + 6
        }
        var xr = x1
        for (id, t) in right.reversed() {
            let w = max(Self.buttonW, DlgMeasure.dlu(t, extra: 30))
            xr -= w
            add(.button, id, xr, y, w, Self.buttonH, S.base | S.tab | (id == IDC.ok ? 1 : 0), t)
            xr -= 6
        }
        y += Self.buttonH + 6
    }

    // MARK: - 中身

    private enum S {
        static let base: UInt32 = 0x5000_0000      // WS_CHILD | WS_VISIBLE
        static let disabled: UInt32 = 0x0800_0000  // WS_DISABLED
        static let group: UInt32 = 0x0002_0000     // WS_GROUP(ラジオボタンのまとまりの始まり)
        static let tab: UInt32 = 0x0001_0000       // WS_TABSTOP
        static let vscroll: UInt32 = 0x0020_0000   // WS_VSCROLL
    }

    private static func alignBits(_ a: Align) -> UInt32 {
        switch a {
        case .left: return 0
        case .center: return 1
        case .right: return 2
        }
    }

    private mutating func add(_ cls: DlgClass, _ id: Int, _ x: Int, _ y: Int, _ w: Int, _ h: Int, _ style: UInt32, _ title: String = "") {
        items.append(DlgItem(cls, id, x, y, w, h, style, title))
    }

    private func width(of c: Cell) -> Int {
        switch c {
        case let .text(s, w, _, _): return w ?? DlgMeasure.dlu(s, extra: 3)
        case let .field(_, w, _, _): return w
        case let .check(_, s, w, _): return w ?? DlgMeasure.dlu(s, extra: 22)
        case let .radio(_, s, w, _, _): return w ?? DlgMeasure.dlu(s, extra: 22)
        case let .popup(_, w, _): return w
        case let .combo(_, w): return w
        case .color: return 26
        case let .push(_, s, w): return w ?? max(40, DlgMeasure.dlu(s, extra: 28))
        case let .gap(n): return n
        }
    }

    private mutating func place(_ c: Cell, x: Int, w: Int, tall: Bool) {
        switch c {
        case let .text(s, _, id, align):
            add(.label, id, x, y + (tall ? 2 : 0), w, 10, S.base | Self.alignBits(align), s)
        case let .field(id, _, readOnly, disabled):
            add(.edit, id, x, y, w, Self.fieldH, S.base | S.tab | 0x80 | (readOnly ? 0x800 : 0) | (disabled ? S.disabled : 0))
        case let .check(id, s, _, disabled):
            add(.button, id, x, y + (tall ? 1 : 0), w, 10, S.base | S.tab | 3 | (disabled ? S.disabled : 0), s)
        case let .radio(id, s, _, first, manual):
            add(.button, id, x, y + (tall ? 1 : 0), w, 10, S.base | (manual ? 4 : 9) | (first ? S.group | S.tab : 0), s)
        case let .popup(id, _, owner):
            add(.comboBox, id, x, y, w, 80, S.base | S.tab | S.vscroll | 3 | (owner ? 0x10 : 0))
        case let .combo(id, _):
            add(.comboBox, id, x, y, w, 80, S.base | S.tab | S.vscroll | 2 | 0x40)
        case let .color(id):
            add(.button, id, x, y, w, 13, S.base | S.tab | 0xB)
        case let .push(id, s, _):
            add(.button, id, x, y - 1, w, Self.buttonH, S.base | S.tab | (id == IDC.ok ? 1 : 0), s)
        case .gap:
            break
        }
    }
}

/// 文字の幅を、画面と同じ 11 点のシステムの文字で測る
enum DlgMeasure {
    static func points(_ s: String) -> CGFloat {
        let font = CTFontCreateUIFontForLanguage(.system, 11, nil)
        let attrs: [NSAttributedString.Key: Any] = font.map { [NSAttributedString.Key(kCTFontAttributeName as String): $0] } ?? [:]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: s, attributes: attrs))
        return CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
    }

    static func dlu(_ s: String, extra: CGFloat = 0) -> Int {
        Int(ceil((points(s) + extra) / DLU.x))
    }
}
