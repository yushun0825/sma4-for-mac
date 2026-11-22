import AppKit

/// ダイアログのウインドウ。文字を打っている欄では、メニューの割り当てに関係なく ⌘X・⌘C・⌘V・⌘A・⌘Z を文字の編集に使う
@MainActor
final class DialogPanel: NSPanel {
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) { onCancel?() }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if let tv = firstResponder as? NSTextView, mods == .command || mods == [.command, .shift],
           let ch = event.charactersIgnoringModifiers?.lowercased() {
            switch (ch, mods == .command) {
            case ("x", true): tv.cut(nil); return true
            case ("c", true): tv.copy(nil); return true
            case ("v", true): tv.paste(nil); return true
            case ("a", true): tv.selectAll(nil); return true
            case ("z", true): tv.undoManager?.undo(); return true
            case ("z", false): tv.undoManager?.redo(); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Win32 の DialogBox にあたる、1 枚のダイアログ。run で閉じるまで待ち、閉じたボタンの ID を返す
@MainActor
final class Dialog: NSObject, NSWindowDelegate {
    let panel: DialogPanel
    let page: TemplateView
    private(set) var result = IDC.cancel
    /// OK を押したとき(false を返すと閉じない)
    var validate: (() -> Bool)?
    /// そのほかの押しボタン。true を返すとその ID で閉じる
    var buttons: [Int: () -> Bool] = [:]
    private var running = false

    init(_ t: DlgTemplate, title: String? = nil) {
        page = TemplateView(t)
        let size = page.frame.size
        panel = DialogPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable],
                            backing: .buffered, defer: true)
        super.init()
        panel.title = title ?? (t.title.isEmpty ? "Sma4 for Mac" : t.title)
        let content = FlippedView(frame: NSRect(origin: .zero, size: size))
        content.addSubview(page)
        panel.contentView = content
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.worksWhenModal = true
        panel.hidesOnDeactivate = false
        page.onPush = { [weak self] id in self?.pushed(id) }
        panel.onCancel = { [weak self] in self?.end(IDC.cancel) }
    }

    private func pushed(_ id: Int) {
        if let h = buttons[id] {
            if h() { end(id) }
            return
        }
        if id == IDC.ok {
            if validate?() ?? true { end(IDC.ok) }
        } else if id == IDC.cancel {
            end(IDC.cancel)
        }
    }

    func end(_ id: Int) {
        result = id
        if running { NSApp.stopModal() } else { panel.orderOut(nil) }
    }

    /// 閉じるまで待つ(Win32 の DialogBox と同じ)
    @discardableResult
    func run(over parent: NSWindow?) -> Int {
        if DialogCapture.isActive {
            DialogCapture.capture(panel, tabs: nil)
            result = IDC.cancel
            return result
        }
        Dialog.place(panel, over: parent)
        panel.makeKeyAndOrderFront(nil)
        if let f = page.firstField { panel.makeFirstResponder(f) }
        running = true
        NSApp.runModal(for: panel)
        running = false
        panel.orderOut(nil)
        return result
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        end(IDC.cancel)
        return false
    }

    static func place(_ w: NSWindow, over parent: NSWindow?) {
        if let p = parent, p.isVisible {
            let f = p.frame
            let s = w.frame.size
            var o = NSPoint(x: f.midX - s.width / 2, y: f.maxY - s.height - min(90, f.height * 0.15))
            if let screen = p.screen?.visibleFrame {
                o.x = max(screen.minX, min(o.x, screen.maxX - s.width))
                o.y = max(screen.minY, min(o.y, screen.maxY - s.height))
            }
            w.setFrameOrigin(o)
        } else {
            w.center()
        }
    }
}

/// Win32 の PropertySheet(タブの付いたダイアログ)。ボタンは右下にキャンセル・OK の順(OK がいちばん右)
@MainActor
final class PropertySheet: NSObject, NSWindowDelegate {
    let panel: DialogPanel
    let tabView = NSTabView()
    private(set) var pages: [TemplateView] = []
    private(set) var result = IDC.cancel
    var validate: (() -> Bool)?
    /// ページの中の押しボタン(ページの番号, ID)。true を返すとその ID で閉じる
    var buttons: [Int: () -> Bool] = [:]
    private var running = false

    init(title: String, pages list: [(String, DlgTemplate)], start: Int = 0) {
        let views = list.map { TemplateView($0.1) }
        pages = views
        let w = views.map(\.frame.width).max() ?? 200
        let h = views.map(\.frame.height).max() ?? 150
        // タブの中身の大きさが元のページと同じになるように、枠の大きさを測って決める
        tabView.tabViewType = .topTabsBezelBorder
        tabView.font = TemplateView.font
        tabView.controlSize = .small
        tabView.frame = NSRect(x: 0, y: 0, width: w + 40, height: h + 60)
        for (k, (name, _)) in list.enumerated() {
            let item = NSTabViewItem(identifier: k)
            item.label = name
            let holder = FlippedView(frame: NSRect(x: 0, y: 0, width: w, height: h))
            holder.addSubview(views[k])
            item.view = holder
            tabView.addTabViewItem(item)
        }
        let cr = tabView.contentRect
        let tabSize = NSSize(width: w + (tabView.frame.width - cr.width), height: h + (tabView.frame.height - cr.height))
        let margin: CGFloat = 10
        let buttonW: CGFloat = 50 * DLU.x, buttonH: CGFloat = 22, gap: CGFloat = 6 * DLU.x
        let contentSize = NSSize(width: tabSize.width + margin * 2, height: margin + tabSize.height + 8 + buttonH + margin)
        panel = DialogPanel(contentRect: NSRect(origin: .zero, size: contentSize), styleMask: [.titled, .closable],
                            backing: .buffered, defer: true)
        super.init()
        panel.title = title
        let content = FlippedView(frame: NSRect(origin: .zero, size: contentSize))
        tabView.frame = NSRect(x: margin, y: margin, width: tabSize.width, height: tabSize.height)
        content.addSubview(tabView)
        let ok = NSButton(title: "OK", target: self, action: #selector(okPressed(_:)))
        let cancel = NSButton(title: "キャンセル", target: self, action: #selector(cancelPressed(_:)))
        for (i, b) in [cancel, ok].enumerated() {
            b.bezelStyle = .push
            b.controlSize = .small
            b.font = TemplateView.font
            let x = contentSize.width - margin - CGFloat(2 - i) * buttonW - CGFloat(1 - i) * gap
            b.frame = NSRect(x: x - 4, y: margin + tabSize.height + 8, width: buttonW + 8, height: buttonH)
            content.addSubview(b)
        }
        ok.keyEquivalent = "\r"
        cancel.keyEquivalent = "\u{1b}"
        panel.contentView = content
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.worksWhenModal = true
        panel.hidesOnDeactivate = false
        panel.onCancel = { [weak self] in self?.end(IDC.cancel) }
        for p in views {
            p.onPush = { [weak self] id in self?.pushed(id) }
        }
        if start < list.count { tabView.selectTabViewItem(at: start) }
    }

    func page(_ i: Int) -> TemplateView { pages[i] }

    private func pushed(_ id: Int) {
        if let h = buttons[id], h() { end(id) }
    }

    @objc private func okPressed(_ sender: Any?) {
        if validate?() ?? true { end(IDC.ok) }
    }

    @objc private func cancelPressed(_ sender: Any?) { end(IDC.cancel) }

    func end(_ id: Int) {
        result = id
        if running { NSApp.stopModal() } else { panel.orderOut(nil) }
    }

    @discardableResult
    func run(over parent: NSWindow?) -> Int {
        if DialogCapture.isActive {
            DialogCapture.capture(panel, tabs: tabView)
            result = IDC.cancel
            return result
        }
        Dialog.place(panel, over: parent)
        panel.makeKeyAndOrderFront(nil)
        if let i = tabView.selectedTabViewItem.map({ tabView.indexOfTabViewItem($0) }), i < pages.count, let f = pages[i].firstField {
            panel.makeFirstResponder(f)
        }
        running = true
        NSApp.runModal(for: panel)
        running = false
        panel.orderOut(nil)
        return result
    }

    var isOK: Bool { result == IDC.ok }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        end(IDC.cancel)
        return false
    }
}

/// Win32 の MessageBox にあたるもの
@MainActor
enum MessageBox {
    @discardableResult
    static func show(_ text: String, title: String = "Sma4 for Mac", buttons: [String] = ["OK"], style: NSAlert.Style = .informational) -> Int {
        let a = NSAlert()
        a.alertStyle = style
        let lines = text.components(separatedBy: "\n")
        a.messageText = lines.count > 1 && title == "Sma4 for Mac" ? lines[0] : (title == "Sma4 for Mac" ? text : title)
        a.informativeText = lines.count > 1 && title == "Sma4 for Mac" ? lines.dropFirst().joined(separator: "\n") : (title == "Sma4 for Mac" ? "" : text)
        for b in buttons { a.addButton(withTitle: b) }
        let r = a.runModal()
        return r.rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    }

    /// はい・いいえ(はいなら true)
    static func confirm(_ text: String, title: String = "確認", yes: String = "OK", no: String = "キャンセル") -> Bool {
        show(text, title: title, buttons: [yes, no]) == 0
    }
}


/// 確認用: ダイアログを出す代わりに、画面の外で PNG にする(--snapshot のときだけ)
@MainActor
enum DialogCapture {
    static var outDir: URL?
    static var name = "dialog"
    static var isActive: Bool { outDir != nil }

    static func capture(_ w: NSWindow, tabs: NSTabView?) {
        guard let dir = outDir else { return }
        w.setFrameOrigin(NSPoint(x: -9000, y: -9000))
        w.orderFrontRegardless()
        if let tabs, tabs.numberOfTabViewItems > 1 {
            for i in 0..<tabs.numberOfTabViewItems {
                tabs.selectTabViewItem(at: i)
                save(w, to: dir.appendingPathComponent("\(name)-\(i + 1).png"))
            }
        } else {
            save(w, to: dir.appendingPathComponent("\(name).png"))
        }
        w.orderOut(nil)
    }

    /// 窓の中身を、タイトルバーの代わりに題名の帯を付けて PNG にする
    static func save(_ w: NSWindow, to url: URL) {
        let until = Date().addingTimeInterval(0.25)
        while Date() < until { RunLoop.current.run(until: Date().addingTimeInterval(0.03)) }
        guard let view = w.contentView else { return }
        view.layoutSubtreeIfNeeded()
        view.displayIfNeeded()
        let size = view.bounds.size
        let titleH: CGFloat = 24
        let scale: CGFloat = 2
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let full = NSImage(size: NSSize(width: size.width, height: size.height + titleH))
        full.lockFocus()
        NSColor.windowBackgroundColor.setFill()
        NSRect(x: 0, y: 0, width: size.width, height: size.height + titleH).fill()
        rep.draw(in: NSRect(x: 0, y: 0, width: size.width, height: size.height))
        NSColor(calibratedWhite: 0.86, alpha: 1).setFill()
        NSRect(x: 0, y: size.height, width: size.width, height: titleH).fill()
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 12), .foregroundColor: NSColor.black]
        let t = w.title as NSString
        let ts = t.size(withAttributes: attrs)
        t.draw(at: NSPoint(x: (size.width - ts.width) / 2, y: size.height + (titleH - ts.height) / 2), withAttributes: attrs)
        full.unlockFocus()
        guard let cg = full.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
        let bmp = NSBitmapImageRep(cgImage: cg)
        bmp.size = full.size
        _ = scale
        try? bmp.representation(using: .png, properties: [:])?.write(to: url)
    }
}
