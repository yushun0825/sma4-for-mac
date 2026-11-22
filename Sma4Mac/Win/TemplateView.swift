import AppKit
import Sma4Core

/// ダイアログ 1 枚(DlgTemplate)を、配置(DLU)どおりに Mac の部品で並べたビュー。
/// 部品は Win32 と同じ ID で引ける。
@MainActor
final class TemplateView: NSView, NSTextFieldDelegate, NSComboBoxDelegate {
    static let font = NSFont.systemFont(ofSize: 11)
    static let smallFont = NSFont.systemFont(ofSize: 10)

    let template: DlgTemplate
    private(set) var controls: [Int: NSView] = [:]
    private var labels: [NSTextField] = []
    private var handlers: [Int: () -> Void] = [:]
    /// 押しボタンが押されたとき(ダイアログの外枠が OK・キャンセルなどを受ける)
    var onPush: ((Int) -> Void)?
    /// どれかの値が変わったとき(見本の描き直しなど)
    var onAnyChange: (() -> Void)?

    init(_ t: DlgTemplate) {
        template = t
        super.init(frame: NSRect(origin: .zero, size: DLU.size(t)))
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    // MARK: - 組み立て

    private func build() {
        // 枠(グループボックス・黒枠)は後ろに置く
        for item in template.items where item.isGroupBox || (item.cls == .label && (4...9).contains(item.kind)) {
            let v: NSView = item.isGroupBox ? GroupBoxView(title: DlgText.strip(item.title)) : FrameLineView()
            v.frame = DLU.rect(item)
            addSubview(v)
            if item.id != IDC.static { controls[item.id] = v }
        }
        // ラジオボタンのまとまり(Win32 と同じく WS_GROUP から次の WS_GROUP まで)
        var groupIndex = 0
        var groupOf: [Int: Int] = [:]
        var members: [Int: [DlgItem]] = [:]
        for (k, item) in template.items.enumerated() {
            if item.startsGroup { groupIndex += 1 }
            if item.isRadio {
                // 自動のラジオボタン(BS_AUTORADIOBUTTON)だけをまとめる。手動のものは 1 つずつ
                let g = item.kind == 9 ? groupIndex : 100_000 + k
                groupOf[k] = g
                members[g, default: []].append(item)
            }
        }
        var containers: [Int: NSView] = [:]
        for (g, items) in members {
            let union = items.map { DLU.rect($0) }.reduce(NSRect.null) { $0.union($1) }
            let c = FlippedView(frame: union)
            containers[g] = c
        }
        for (k, item) in template.items.enumerated() {
            if item.isGroupBox || (item.cls == .label && (4...9).contains(item.kind)) { continue }
            let rect = DLU.rect(item)
            var view: NSView
            switch item.cls {
            case .label:
                view = makeLabel(item, rect)
            case .button:
                if item.isOwnerDrawButton {
                    view = item.isDisabled ? SampleView(frame: rect) : makeColorWell(rect)
                } else if item.isCheckBox {
                    view = makeToggle(item, rect, radio: false)
                } else if item.isRadio, let g = groupOf[k], let c = containers[g] {
                    let b = makeToggle(item, rect, radio: true)
                    b.frame.origin.x -= c.frame.minX
                    b.frame.origin.y -= c.frame.minY
                    c.addSubview(b)
                    if c.superview == nil { addSubview(c) }
                    controls[item.id] = b
                    continue
                } else {
                    view = makePushButton(item, rect)
                }
            case .edit:
                view = item.isMultiline ? makeTextArea(item, rect) : makeField(item, rect)
            case .comboBox:
                view = item.isDropDownList ? makePopup(item, rect) : makeComboBox(item, rect)
            case .listBox:
                let l = ListBox(frame: rect, multiple: item.isMultiSelectList, horizontalScroll: item.hasHorizontalScroll)
                l.onSelect = { [weak self] in self?.fire(item.id) }
                view = l
            case .scrollBar:
                let s = NSSlider(value: 0, minValue: 0, maxValue: 1, target: self, action: #selector(changed(_:)))
                s.controlSize = .small
                s.frame = rect.insetBy(dx: 0, dy: -3)
                s.tag = item.id
                view = s
            }
            if item.isDisabled, let c = view as? NSControl { c.isEnabled = false }
            addSubview(view)
            if item.id != IDC.static || item.cls != .label { controls[item.id] = view }
        }
    }

    private func makeLabel(_ item: DlgItem, _ rect: NSRect) -> NSView {
        if item.kind == 3 {
            // アイコン(「について」の画面)
            let iv = NSImageView(frame: NSRect(x: rect.midX - 16, y: rect.minY, width: 32, height: 32))
            iv.image = NSApp.applicationIconImage
            iv.imageScaling = .scaleProportionallyUpOrDown
            return iv
        }
        let text = DlgText.strip(item.title)
        let l = NSTextField(wrappingLabelWithString: text)
        l.font = TemplateView.font
        l.alignment = item.kind == 1 ? .center : (item.kind == 2 ? .right : .left)
        l.isSelectable = false
        l.textColor = .labelColor
        l.lineBreakMode = .byCharWrapping
        // 文字は 1 行ぶんの高さの中で上から描く(Win32 の STATIC と同じ)。
        // 1 行の見出しは、Mac の文字が少し広いぶん、右(右寄せなら左)へはみ出してよいことにする
        var frame = NSRect(x: rect.minX, y: rect.minY, width: rect.width + 2, height: max(rect.height, 14))
        let need = ceil((text as NSString).size(withAttributes: [.font: TemplateView.font]).width) + 4
        if rect.height <= 12 * DLU.y, need > frame.width {
            let extra = min(need - frame.width, frame.width * 0.4)
            if item.kind == 2 { frame.origin.x -= extra } else if item.kind == 1 { frame.origin.x -= extra / 2 }
            frame.size.width += extra
        }
        l.frame = frame
        labels.append(l)
        return l
    }

    private func makePushButton(_ item: DlgItem, _ rect: NSRect) -> NSView {
        let b = NSButton(title: DlgText.strip(item.title), target: self, action: #selector(pushed(_:)))
        b.font = TemplateView.font
        b.tag = item.id
        if rect.width < 36 || rect.height < 16 {
            // 小さなボタン(<<< など)は、余白の少ない形で枠いっぱいに描く
            b.bezelStyle = .smallSquare
            b.controlSize = .small
            b.font = TemplateView.smallFont
            b.frame = rect.insetBy(dx: -1, dy: 0)
        } else {
            b.bezelStyle = .push
            b.controlSize = .small
            let h = max(b.intrinsicContentSize.height, 20)
            // Mac の押しボタンは枠の内側に余白があるので、見えるボタンが元の大きさになるよう左右に広げる
            b.frame = NSRect(x: rect.minX - 4, y: rect.midY - h / 2, width: rect.width + 8, height: h)
        }
        if item.id == IDC.ok || item.isDefaultButton { b.keyEquivalent = "\r" }
        if item.id == IDC.cancel { b.keyEquivalent = "\u{1b}" }
        return b
    }

    private func makeToggle(_ item: DlgItem, _ rect: NSRect, radio: Bool) -> NSButton {
        let title = DlgText.strip(item.title)
        let b = radio ? NSButton(radioButtonWithTitle: title, target: self, action: #selector(toggled(_:)))
                      : NSButton(checkboxWithTitle: title, target: self, action: #selector(toggled(_:)))
        b.font = TemplateView.font
        b.controlSize = .small
        b.tag = item.id
        let h = max(rect.height, 15)
        b.frame = NSRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width + 12, height: h)
        if item.isDisabled { b.isEnabled = false }
        return b
    }

    private func makeColorWell(_ rect: NSRect) -> NSView {
        let w = NSColorWell(style: .default)
        w.frame = rect
        w.target = self
        w.action = #selector(changed(_:))
        return w
    }

    private func makeField(_ item: DlgItem, _ rect: NSRect) -> NSView {
        let f = NSTextField(string: "")
        f.font = TemplateView.font
        f.controlSize = .small
        f.isBezeled = true
        f.bezelStyle = .squareBezel
        f.cell?.isScrollable = true
        f.cell?.wraps = false
        f.usesSingleLineMode = true
        f.isEditable = !item.isReadOnly
        f.isSelectable = true
        f.delegate = self
        f.tag = item.id
        let h = max(rect.height, 19)
        f.frame = NSRect(x: rect.minX, y: rect.midY - h / 2, width: rect.width, height: h)
        // 狭い欄(数を入れるだけのもの)は少し小さな文字にして、桁が隠れないようにする
        if rect.width < 46 { f.font = TemplateView.smallFont }
        if item.isReadOnly { f.drawsBackground = false }
        return f
    }

    private func makeTextArea(_ item: DlgItem, _ rect: NSRect) -> NSView {
        let sv = NSTextView.scrollableTextView()
        sv.frame = rect
        sv.borderType = .bezelBorder
        sv.hasVerticalScroller = true
        if let tv = sv.documentView as? NSTextView {
            tv.font = TemplateView.font
            tv.isRichText = false
            tv.allowsUndo = true
            tv.isAutomaticQuoteSubstitutionEnabled = false
            tv.isAutomaticDashSubstitutionEnabled = false
            tv.isAutomaticTextReplacementEnabled = false
            tv.isAutomaticSpellingCorrectionEnabled = false
            tv.isEditable = !item.isReadOnly
            tv.textContainerInset = NSSize(width: 2, height: 2)
        }
        return sv
    }

    private func makePopup(_ item: DlgItem, _ rect: NSRect) -> NSView {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        p.font = TemplateView.font
        p.controlSize = .small
        p.target = self
        p.action = #selector(changed(_:))
        p.tag = item.id
        p.frame = NSRect(x: rect.minX - 2, y: rect.minY - 1, width: rect.width + 4, height: 22)
        return p
    }

    private func makeComboBox(_ item: DlgItem, _ rect: NSRect) -> NSView {
        let c = NSComboBox(frame: .zero)
        c.font = TemplateView.font
        c.controlSize = .small
        c.completes = false
        c.numberOfVisibleItems = 12
        c.target = self
        c.action = #selector(changed(_:))
        c.delegate = self
        c.tag = item.id
        c.frame = NSRect(x: rect.minX, y: rect.minY - 1, width: rect.width, height: 22)
        return c
    }

    // MARK: - 出来事

    @objc private func pushed(_ sender: NSButton) {
        handlers[sender.tag]?()
        onPush?(sender.tag)
    }

    @objc private func toggled(_ sender: NSButton) { fire(sender.tag) }

    @objc private func changed(_ sender: NSControl) {
        if let w = sender as? NSColorWell, let id = controls.first(where: { $0.value === w })?.key {
            fire(id); return
        }
        fire(sender.tag)
    }

    func controlTextDidChange(_ obj: Notification) {
        if let f = obj.object as? NSControl { fire(f.tag) }
    }

    func comboBoxSelectionDidChange(_ notification: Notification) {
        guard let c = notification.object as? NSComboBox else { return }
        // 選んだ直後は stringValue がまだ古いので、次の周回で知らせる
        DispatchQueue.main.async { [weak self] in self?.fire(c.tag) }
    }

    private func fire(_ id: Int) {
        handlers[id]?()
        onAnyChange?()
    }

    /// 部品が押された・変わったときの処理を登録する
    func on(_ id: Int, _ handler: @escaping () -> Void) { handlers[id] = handler }

    // MARK: - 部品を引く

    func view(_ id: Int) -> NSView? { controls[id] }
    func button(_ id: Int) -> NSButton? { controls[id] as? NSButton }
    func field(_ id: Int) -> NSTextField? { controls[id] as? NSTextField }
    func popup(_ id: Int) -> NSPopUpButton? { controls[id] as? NSPopUpButton }
    func comboBox(_ id: Int) -> NSComboBox? { controls[id] as? NSComboBox }
    func list(_ id: Int) -> ListBox? { controls[id] as? ListBox }
    func slider(_ id: Int) -> NSSlider? { controls[id] as? NSSlider }
    func colorWell(_ id: Int) -> NSColorWell? { controls[id] as? NSColorWell }
    func sample(_ id: Int) -> SampleView? { controls[id] as? SampleView }
    func textView(_ id: Int) -> NSTextView? { (controls[id] as? NSScrollView)?.documentView as? NSTextView }

    // MARK: - 値

    func text(_ id: Int) -> String {
        switch controls[id] {
        case let c as NSComboBox: return c.stringValue
        case let f as NSTextField: return f.stringValue
        case let p as NSPopUpButton: return p.titleOfSelectedItem ?? ""
        case let b as NSButton: return b.title
        case let g as GroupBoxView: return g.title
        default: return textView(id)?.string ?? ""
        }
    }

    func setText(_ id: Int, _ s: String) {
        switch controls[id] {
        case let c as NSComboBox: c.stringValue = s
        case let f as NSTextField: f.stringValue = s
        case let b as NSButton: b.title = s
        case let g as GroupBoxView: g.title = s
        default: textView(id)?.string = s
        }
    }

    /// 数(打ち込めないときは nil)
    func number(_ id: Int) -> Double? {
        let s = text(id).trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return nil }
        return Double(s) ?? DataParser.number(s)
    }

    func number(_ id: Int, or fallback: Double) -> Double { number(id) ?? fallback }

    func integer(_ id: Int, or fallback: Int) -> Int {
        guard let v = number(id), v.isFinite else { return fallback }
        return Int(v.rounded())
    }

    /// C の %g と同じ書き方で入れる
    func setNumber(_ id: Int, _ v: Double, format: String = "%g") {
        setText(id, String(format: format, v))
    }

    func setInteger(_ id: Int, _ v: Int) { setText(id, String(v)) }

    /// 0.01 mm の整数を mm で
    func setMM(_ id: Int, _ hundredths: Int) { setText(id, Num.mm(hundredths)) }
    func mm(_ id: Int, or fallback: Int) -> Int {
        guard let v = number(id), v.isFinite else { return fallback }
        return Int((v * 100).rounded())
    }

    func isChecked(_ id: Int) -> Bool { button(id)?.state == .on }
    func setChecked(_ id: Int, _ on: Bool) { button(id)?.state = on ? .on : .off }

    func setEnabled(_ id: Int, _ on: Bool) {
        switch controls[id] {
        case let c as NSControl: c.isEnabled = on
        case let s as NSScrollView: (s.documentView as? NSTextView)?.isEditable = on
        default: break
        }
    }

    func setHidden(_ id: Int, _ hidden: Bool) { controls[id]?.isHidden = hidden }

    func setItems(_ id: Int, _ titles: [String]) {
        if let p = popup(id) {
            p.removeAllItems()
            for t in titles { p.menu?.addItem(NSMenuItem(title: t, action: nil, keyEquivalent: "")) }
        } else if let c = comboBox(id) {
            c.removeAllItems()
            c.addItems(withObjectValues: titles)
        } else if let l = list(id) {
            l.items = titles
        }
    }

    /// 絵の付いた選択肢(プロットタイプ・線種・色など)
    func setImageItems(_ id: Int, _ items: [(title: String, image: NSImage?)]) {
        guard let p = popup(id) else { return }
        p.removeAllItems()
        for it in items {
            // 絵のある項目は絵だけ。名前は読み上げ用に残す
            let m = NSMenuItem(title: it.image == nil ? it.title : "", action: nil, keyEquivalent: "")
            m.image = it.image
            m.setAccessibilityLabel(it.title)
            p.menu?.addItem(m)
        }
    }

    func selectedIndex(_ id: Int) -> Int {
        if let p = popup(id) { return p.indexOfSelectedItem }
        if let c = comboBox(id) { return c.indexOfSelectedItem }
        if let l = list(id) { return l.selectedIndexes.first ?? -1 }
        return -1
    }

    func select(_ id: Int, _ index: Int) {
        if let p = popup(id) {
            if index >= 0 && index < p.numberOfItems { p.selectItem(at: index) }
        } else if let c = comboBox(id) {
            if index >= 0 && index < c.numberOfItems { c.selectItem(at: index) } else { c.deselectItem(at: c.indexOfSelectedItem) }
        } else if let l = list(id) {
            l.selectedIndexes = index >= 0 ? [index] : []
        }
    }

    func color(_ id: Int) -> SMPColor {
        guard let w = colorWell(id) else { return .black }
        return SMPColor(w.color)
    }

    func setColor(_ id: Int, _ c: SMPColor) { colorWell(id)?.color = c.nsColor }

    /// 見出しの文字(%s などを置き換える)
    func setLabel(_ id: Int, _ s: String) { setText(id, s) }

    /// 最初に文字を打ち込む欄
    var firstField: NSView? {
        for item in template.items where item.cls == .edit && !item.isDisabled && !item.isReadOnly {
            if let v = controls[item.id] {
                if let s = v as? NSScrollView { return s.documentView }
                return v
            }
        }
        return nil
    }
}

/// 上から下へ座標をとるビュー(ラジオボタンのまとまりの入れ物)
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Win32 のグループボックス(枠の上の辺に見出し)。色と線は Mac のものにしている
final class GroupBoxView: NSView {
    var title: String { didSet { needsDisplay = true } }

    init(title: String) {
        self.title = title
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let attrs: [NSAttributedString.Key: Any] = [.font: TemplateView.font, .foregroundColor: NSColor.labelColor]
        let size = (title as NSString).size(withAttributes: attrs)
        let top = floor(size.height / 2) + 0.5
        let box = NSRect(x: 0.5, y: top, width: bounds.width - 1, height: bounds.height - top - 0.5)
        let path = NSBezierPath(roundedRect: box, xRadius: 4, yRadius: 4)
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        if !title.isEmpty {
            NSGraphicsContext.saveGraphicsState()
            let gap = NSRect(x: 6, y: 0, width: size.width + 6, height: size.height)
            let clip = NSBezierPath(rect: bounds)
            clip.append(NSBezierPath(rect: gap).reversed)
            clip.addClip()
            path.stroke()
            NSGraphicsContext.restoreGraphicsState()
            (title as NSString).draw(at: NSPoint(x: 9, y: 0), withAttributes: attrs)
        } else {
            path.stroke()
        }
    }
}

/// Win32 の SS_BLACKFRAME(細い枠)
final class FrameLineView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        NSColor.separatorColor.setStroke()
        let p = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: 4, yRadius: 4)
        p.lineWidth = 1
        p.stroke()
    }
}

/// 見本を描くだけの部品(プロットタイプの見本など)
final class SampleView: NSView {
    var drawer: ((CGContext, NSRect) -> Void)? { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        NSColor.separatorColor.setStroke()
        NSBezierPath(rect: bounds.insetBy(dx: 0.5, dy: 0.5)).stroke()
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.saveGState()
        drawer?(ctx, bounds)
        ctx.restoreGState()
    }
}

extension SMPColor {
    init(_ c: NSColor) {
        let s = c.usingColorSpace(.sRGB) ?? c
        self.init(r: UInt8(max(0, min(255, (s.redComponent * 255).rounded()))),
                  g: UInt8(max(0, min(255, (s.greenComponent * 255).rounded()))),
                  b: UInt8(max(0, min(255, (s.blueComponent * 255).rounded()))))
    }

    var nsColor: NSColor {
        NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }

    var cgColor: CGColor {
        CGColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
    }
}

/// 数の書き方(SMP の書式に合わせる)
enum Num {
    /// C の %g
    static func g(_ v: Double) -> String { String(format: "%g", v) }
    /// 0.01 mm の整数を mm の文字に(余分な 0 は付けない)
    static func mm(_ hundredths: Int) -> String {
        let v = Double(hundredths) / 100
        return String(format: "%g", v)
    }
    /// "%6.2lf" と同じ
    static func f2(_ v: Double) -> String { String(format: "%.2f", v) }
}
