import AppKit

/// ダイアログの部品の種類(Win32 の定義済みクラスの名前を借りている)
enum DlgClass: Sendable { case button, edit, label, listBox, scrollBar, comboBox }

/// ダイアログの部品 1 つ(位置と大きさはダイアログ単位 = DLU のまま)
struct DlgItem: Sendable {
    let cls: DlgClass
    let id: Int
    let x: Int
    let y: Int
    let cx: Int
    let cy: Int
    let style: UInt32
    let title: String

    init(_ cls: DlgClass, _ id: Int, _ x: Int, _ y: Int, _ cx: Int, _ cy: Int, _ style: UInt32, _ title: String) {
        self.cls = cls; self.id = id; self.x = x; self.y = y; self.cx = cx; self.cy = cy
        self.style = style; self.title = title
    }

    /// BS_・SS_ の下位 4 ビット
    var kind: UInt32 { style & 0xF }
    var isDisabled: Bool { style & 0x0800_0000 != 0 }
    var isVisible: Bool { style & 0x1000_0000 != 0 }
    /// WS_GROUP(ラジオボタンのまとまりの始まり)
    var startsGroup: Bool { style & 0x0002_0000 != 0 }

    var isPushButton: Bool { cls == .button && (kind == 0 || kind == 1) }
    var isDefaultButton: Bool { cls == .button && kind == 1 }
    var isCheckBox: Bool { cls == .button && [2, 3, 5, 6].contains(kind) }
    var isRadio: Bool { cls == .button && (kind == 4 || kind == 9) }
    var isGroupBox: Bool { cls == .button && kind == 7 }
    var isOwnerDrawButton: Bool { cls == .button && kind == 0xB }

    var isMultiline: Bool { cls == .edit && style & 0x4 != 0 }
    var isReadOnly: Bool { cls == .edit && style & 0x800 != 0 }

    /// CBS_DROPDOWNLIST(選ぶだけ)か CBS_DROPDOWN(打ち込める)か
    var isDropDownList: Bool { cls == .comboBox && style & 0x3 == 3 }
    var isOwnerDrawCombo: Bool { cls == .comboBox && style & 0x30 != 0 }

    var isMultiSelectList: Bool { cls == .listBox && style & 0x0808 != 0 }
    var isOwnerDrawList: Bool { cls == .listBox && style & 0x30 != 0 }
    var hasHorizontalScroll: Bool { style & 0x0010_0000 != 0 }
}

/// ダイアログ 1 枚(リソースの DIALOG)
struct DlgTemplate: Sendable {
    let name: String
    let title: String
    let cx: Int
    let cy: Int
    let style: UInt32
    let items: [DlgItem]

    func item(_ id: Int) -> DlgItem? { items.first { $0.id == id } }
}

enum DlgText {
    /// Windows のアクセスキーの印を外す。"線幅(&W)" → "線幅"、"&From:" → "From:"、"&&" → "&"
    /// (Mac にはアクセスキーが無いので、押しても動かない印は出さない)
    static func strip(_ s: String) -> String {
        var t = s
        // (&X) と全角の(&X)
        if let re = try? NSRegularExpression(pattern: "[(（]&[^)）][)）]") {
            t = re.stringByReplacingMatches(in: t, range: NSRange(t.startIndex..., in: t), withTemplate: "")
        }
        t = t.replacingOccurrences(of: "&&", with: "\u{1}")
        t = t.replacingOccurrences(of: "&", with: "")
        t = t.replacingOccurrences(of: "\u{1}", with: "&")
        return t
    }
}

/// ダイアログ単位(DLU)→ ポイント。ＭＳ Ｐゴシック 9pt の平均の文字の幅 7・高さ 12 から。
enum DLU {
    static let x: CGFloat = 1.75
    static let y: CGFloat = 1.5

    static func rect(_ i: DlgItem) -> NSRect {
        NSRect(x: CGFloat(i.x) * x, y: CGFloat(i.y) * y, width: CGFloat(i.cx) * x, height: CGFloat(i.cy) * y)
    }

    static func size(_ t: DlgTemplate) -> NSSize {
        NSSize(width: CGFloat(t.cx) * x, height: CGFloat(t.cy) * y)
    }
}

/// Win32 の決まった ID
enum IDC {
    static let ok = 1
    static let cancel = 2
    static let abort = 3
    static let retry = 4
    static let ignore = 5
    static let yes = 6
    static let no = 7
    static let `static` = 65535
}
