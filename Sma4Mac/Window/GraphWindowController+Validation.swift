import AppKit
import Sma4Core

/// メニューとツールバーの、押せる・押せない・チェックの判定
extension GraphWindowController {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let a = item.action
        if let a {
            if isToggle(a) { item.state = isActionOn(a, tag: item.tag) ? .on : .off }
            if a == #selector(selectGraph(_:)) { item.state = item.tag == doc?.activeGraphIndex ? .on : .off }
            if a == #selector(undoAction(_:)) { item.title = undoTitle() }
            if a == #selector(paste(_:)) { item.title = pasteTitle() }
            return isActionEnabled(a, tag: item.tag)
        }
        return true
    }

    func isToggle(_ a: Selector) -> Bool {
        [#selector(togglePreview(_:)), #selector(toggleReadValue(_:)), #selector(beginTrimming(_:)),
         #selector(showAllGraphs(_:)), #selector(showActiveGraphOnly(_:))].contains(a)
    }

    func isActionOn(_ a: Selector, tag: Int = 0) -> Bool {
        guard let doc else { return false }
        switch a {
        case #selector(togglePreview(_:)): return canvas.preview
        case #selector(toggleReadValue(_:)): return canvas.mode == .readValue
        case #selector(beginTrimming(_:)): return canvas.mode == .trimming
        case #selector(showAllGraphs(_:)): return doc.soloGraph == nil
        case #selector(showActiveGraphOnly(_:)): return doc.soloGraph != nil
        default: return false
        }
    }

    func isActionEnabled(_ a: Selector, tag: Int = 0) -> Bool {
        guard let doc else { return false }
        let g = doc.activeGraph
        let hasSeries = !(g?.series.isEmpty ?? true)
        switch a {
        case #selector(showAxisDialog(_:)):
            guard let g else { return false }
            if tag == 2 { return g.frameType == .box && !g.axes[0].commonWithOpposite }
            if tag == 3 { return g.frameType == .box && !g.axes[1].commonWithOpposite }
            return true
        case #selector(clearScale(_:)):
            guard let g else { return false }
            if tag == 2 { return g.uIndependent && hasSeries }
            if tag == 3 { return g.rIndependent && hasSeries }
            return hasSeries
        case #selector(closeDataFile(_:)), #selector(toggleSeriesVisibility(_:)), #selector(editDataFile(_:)),
             #selector(saveData(_:)), #selector(toggleReadValue(_:)), #selector(dataMask(_:)), #selector(copyData(_:)),
             #selector(clearAllScale(_:)), #selector(beginTrimming(_:)), #selector(insertLegend(_:)),
             #selector(leastSquares(_:)), #selector(spline(_:)), #selector(extensionAnalysis(_:)):
            return hasSeries
        case #selector(reanalyze(_:)), #selector(clearAnalysis(_:)), #selector(copyCurveData(_:)):
            return g?.series.contains(where: { $0.kind.hasCurve || $0.extensionAnalysis != nil }) ?? false
        case #selector(evaluateFit(_:)):
            return g?.series.contains(where: { $0.kind.isLSQ }) ?? false
        case #selector(delete(_:)), #selector(copyObject(_:)), #selector(bringForward(_:)), #selector(sendBackward(_:)),
             #selector(editSelected(_:)):
            return !canvas.selection.isEmpty
        case #selector(cutObject(_:)):
            return canvas.selection.count == 1
        case #selector(alignTexts(_:)):
            return selectedTexts().count >= 2
        case #selector(paste(_:)):
            return NSPasteboard.general.data(forType: GraphWindowController.objectPasteboardType) != nil
        case #selector(deleteGraph(_:)), #selector(saveActiveGraph(_:)), #selector(saveAsDefault(_:)):
            return g != nil
        case #selector(addGraph(_:)):
            return doc.project.graphs.count < GraphWindowController.maxGraphs
        case #selector(undoAction(_:)):
            return doc.undoManager?.canUndo ?? false
        case #selector(reorderObjects(_:)):
            return !(g?.objects.isEmpty ?? true)
        case #selector(openDataFile(_:)):
            return (g?.series.count ?? 0) < GraphWindowController.maxSeries
        default:
            return true
        }
    }

    /// 最後の操作によって「取り消す」の名前が変わる
    func undoTitle() -> String {
        guard let name = doc?.undoManager?.undoActionName, doc?.undoManager?.canUndo == true else { return "取り消す" }
        switch name {
        case "削除": return "削除を取り消す"
        case "トリミング", "Clear Scale", "Clear All Scale": return "軸の範囲を元に戻す"
        case "データファイルを閉じる": return "閉じたデータを戻す"
        default: return "取り消す"
        }
    }

    /// クリップボードの中身によって「貼り付け」の名前が変わる
    func pasteTitle() -> String {
        guard let s = NSPasteboard.general.string(forType: GraphWindowController.objectPasteboardType) else { return "ペースト" }
        let objects = SMPReader.legendObjects(lines: s.components(separatedBy: "\n"))
        guard objects.count == 1, let o = objects.first else { return "ペースト" }
        switch o {
        case .shape(let sh): return sh.isBox ? "枠をペースト" : "矢印をペースト"
        case .dot: return "点をペースト"
        case .text: return "文字をペースト"
        default: return "ペースト"
        }
    }
}
