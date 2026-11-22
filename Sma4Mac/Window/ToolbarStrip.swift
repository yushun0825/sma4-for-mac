import AppKit

/// ツールバー(メニューの下のボタンの列)。絵は ToolbarArt で描く。ボタンは Mac の部品。
@MainActor
final class ToolbarStrip: NSView {
    struct Spec {
        let glyph: Int          // ToolbarArt の絵の番号
        let action: Selector
        let hint: String        // ボタンの説明(ステータスバーと吹き出し)
        let toggles: Bool
    }

    typealias W = GraphWindowController

    /// 並びと区切り: [消す] [プレビュー] [開く 印刷] [文字 枠 矢印] [範囲 値を読む 定数] [前へ 後ろへ] [描き直す ヘルプ]
    static let groups: [[Spec]] = [
        [Spec(glyph: 0, action: #selector(W.deleteAllGraphs(_:)), hint: "すべて消す", toggles: false)],
        [Spec(glyph: 2, action: #selector(W.togglePreview(_:)), hint: "プレビュー", toggles: true)],
        [Spec(glyph: 1, action: #selector(W.importGraphs(_:)), hint: "ファイルを開く", toggles: false),
         Spec(glyph: 3, action: #selector(W.printGraphs(_:)), hint: "印刷", toggles: false)],
        [Spec(glyph: 4, action: #selector(W.insertOtherText(_:)), hint: "文字を入れる", toggles: false),
         Spec(glyph: 5, action: #selector(W.insertBox(_:)), hint: "枠を入れる", toggles: false),
         Spec(glyph: 6, action: #selector(W.insertArrow(_:)), hint: "矢印を入れる", toggles: false)],
        [Spec(glyph: 7, action: #selector(W.beginTrimming(_:)), hint: "範囲を決めて拡大する", toggles: true),
         Spec(glyph: 8, action: #selector(W.toggleReadValue(_:)), hint: "値を読む", toggles: true),
         Spec(glyph: 9, action: #selector(W.showConstants(_:)), hint: "定数", toggles: false)],
        [Spec(glyph: 10, action: #selector(W.bringForward(_:)), hint: "前へ", toggles: false),
         Spec(glyph: 11, action: #selector(W.sendBackward(_:)), hint: "後ろへ", toggles: false)],
        [Spec(glyph: 12, action: #selector(W.redraw(_:)), hint: "描き直す", toggles: false),
         Spec(glyph: 13, action: #selector(AppDelegate.showHelp(_:)), hint: "ヘルプ", toggles: false)],
    ]

    static let height: CGFloat = 30
    private(set) var buttons: [(NSButton, Spec)] = []
    /// マウスが乗ったボタンの説明(ステータスバーに出す)
    var onHint: ((String?) -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        var x: CGFloat = 7
        let bw: CGFloat = 26, bh: CGFloat = 24
        for (gi, group) in ToolbarStrip.groups.enumerated() {
            if gi > 0 { x += 9 }
            for spec in group {
                let b = HintButton(frame: NSRect(x: x, y: (ToolbarStrip.height - bh) / 2, width: bw, height: bh))
                b.image = ToolbarStrip.glyph(spec.glyph)
                b.imagePosition = .imageOnly
                b.imageScaling = .scaleNone
                b.bezelStyle = .toolbar
                b.isBordered = true
                b.showsBorderOnlyWhileMouseInside = true
                b.setButtonType(spec.toggles ? .pushOnPushOff : .momentaryPushIn)
                b.action = spec.action
                b.target = nil
                b.toolTip = spec.hint
                b.setAccessibilityLabel(spec.hint)
                b.hint = spec.hint
                b.onHover = { [weak self] h in self?.onHint?(h) }
                addSubview(b)
                buttons.append((b, spec))
                x += bw + 1
            }
        }
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    /// 押せるかどうか・押し込まれているかを、メニューと同じ判定で決め直す
    func validate(with controller: GraphWindowController) {
        for (b, spec) in buttons {
            b.isEnabled = controller.isActionEnabled(spec.action)
            if spec.toggles { b.state = controller.isActionOn(spec.action) ? .on : .off }
        }
    }

    static func glyph(_ n: Int) -> NSImage? { ToolbarArt.glyph(n) }
}

/// マウスが乗ったら説明を知らせるボタン
final class HintButton: NSButton {
    var hint: String?
    var onHover: ((String?) -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.filter { $0.owner === self && $0.userInfo?["hint"] != nil }.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
                                       owner: self, userInfo: ["hint": true]))
    }

    override func mouseEntered(with event: NSEvent) {
        super.mouseEntered(with: event)
        onHover?(hint)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        onHover?(nil)
    }
}

/// ステータスバー(窓のいちばん下の 1 行)
@MainActor
final class StatusBar: NSView {
    static let height: CGFloat = 22
    let label = NSTextField(labelWithString: "")
    let right = NSTextField(labelWithString: "")

    override init(frame: NSRect) {
        super.init(frame: frame)
        for l in [label, right] {
            l.font = .systemFont(ofSize: 11)
            l.textColor = .secondaryLabelColor
            l.lineBreakMode = .byTruncatingTail
            l.translatesAutoresizingMaskIntoConstraints = false
            addSubview(l)
        }
        right.alignment = .right
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            right.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            right.centerYAnchor.constraint(equalTo: centerYAnchor),
            right.leadingAnchor.constraint(greaterThanOrEqualTo: label.trailingAnchor, constant: 12),
        ])
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.windowBackgroundColor.setFill()
        bounds.fill()
        NSColor.separatorColor.setFill()
        NSRect(x: 0, y: bounds.height - 1, width: bounds.width, height: 1).fill()
    }

    var text: String {
        get { label.stringValue }
        set { label.stringValue = newValue }
    }
}
