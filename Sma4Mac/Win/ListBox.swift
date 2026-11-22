import AppKit

/// Win32 の LISTBOX にあたる一覧(1 列・見出しなし)。行を自前で描くこともできる(LBS_OWNERDRAWFIXED)
@MainActor
final class ListBox: NSScrollView, NSTableViewDataSource, NSTableViewDelegate {
    let table = NSTableView()
    var items: [String] = [] { didSet { table.reloadData() } }
    /// 行を描く(nil なら文字だけ)
    var drawRow: ((Int, NSRect, Bool) -> Void)? { didSet { table.reloadData() } }
    var onSelect: (() -> Void)?
    var onDoubleClick: ((Int) -> Void)?
    private var suppress = false

    init(frame: NSRect, multiple: Bool, horizontalScroll: Bool) {
        super.init(frame: frame)
        borderType = .bezelBorder
        hasVerticalScroller = true
        hasHorizontalScroller = horizontalScroll
        autohidesScrollers = true
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("c"))
        col.width = max(frame.width - 4, 40)
        if horizontalScroll { col.width = max(frame.width * 2, 400) }
        table.addTableColumn(col)
        table.headerView = nil
        table.rowHeight = 16
        table.intercellSpacing = NSSize(width: 0, height: 0)
        table.allowsMultipleSelection = multiple
        table.allowsEmptySelection = true
        table.usesAlternatingRowBackgroundColors = false
        table.style = .plain
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.doubleAction = #selector(doubleClicked(_:))
        table.columnAutoresizingStyle = horizontalScroll ? .noColumnAutoresizing : .uniformColumnAutoresizingStyle
        documentView = table
    }

    required init?(coder: NSCoder) { fatalError() }

    var selectedIndexes: IndexSet {
        get { table.selectedRowIndexes }
        set {
            suppress = true
            table.selectRowIndexes(newValue, byExtendingSelection: false)
            if let f = newValue.first { table.scrollRowToVisible(f) }
            suppress = false
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { items.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        if drawRow != nil {
            let v = OwnerDrawRow(frame: NSRect(x: 0, y: 0, width: tableColumn?.width ?? 100, height: 16))
            v.row = row
            v.drawer = { [weak self] r, rect in
                let selected = self?.table.selectedRowIndexes.contains(r) ?? false
                self?.drawRow?(r, rect, selected)
            }
            return v
        }
        let id = NSUserInterfaceItemIdentifier("text")
        let tf: NSTextField
        if let reused = tableView.makeView(withIdentifier: id, owner: self) as? NSTextField {
            tf = reused
        } else {
            tf = NSTextField(labelWithString: "")
            tf.identifier = id
            tf.font = TemplateView.font
            tf.lineBreakMode = .byClipping
        }
        tf.stringValue = row < items.count ? items[row] : ""
        return tf
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        if drawRow != nil { table.reloadData(forRowIndexes: IndexSet(integersIn: 0..<items.count), columnIndexes: [0]) }
        if !suppress { onSelect?() }
    }

    @objc private func doubleClicked(_ sender: Any?) {
        let r = table.clickedRow
        if r >= 0 { onDoubleClick?(r) }
    }
}

final class OwnerDrawRow: NSView {
    var row = 0
    var drawer: ((Int, NSRect) -> Void)?
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) { drawer?(row, bounds) }
}
