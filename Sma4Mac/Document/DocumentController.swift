import AppKit
import UniformTypeIdentifiers
import Sma4Core

/// データファイル(拡張子は何でもよい)も開けるようにする
final class Sma4DocumentController: NSDocumentController {
    override func typeForContents(of url: URL) throws -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "smp" || ext == "sma" { return Sma4Document.smpType }
        if let t = try? super.typeForContents(of: url), t == Sma4Document.smpType { return t }
        return Sma4Document.dataType
    }

    override func runModalOpenPanel(_ openPanel: NSOpenPanel, forTypes types: [String]?) -> Int {
        // Sma4 と同じく「すべてのファイル」を選べるようにする
        openPanel.allowedContentTypes = []
        openPanel.allowsOtherFileTypes = true
        openPanel.message = "グラフ(SMP)か、データファイル(CSV・TXT・DAT など)を選んでください。"
        return super.runModalOpenPanel(openPanel, forTypes: nil)
    }

    override func makeDocument(withContentsOf url: URL, ofType typeName: String) throws -> NSDocument {
        if typeName == Sma4Document.smpType {
            return try super.makeDocument(withContentsOf: url, ofType: typeName)
        }
        // データファイルは新しい(名前のない)グラフとして開く。元のファイルを SMP で上書きしないため。
        guard let doc = try makeUntitledDocument(ofType: Sma4Document.smpType) as? Sma4Document else {
            throw CocoaError(.fileReadUnknown)
        }
        try doc.read(from: url, ofType: typeName)
        doc.suggestedBaseName = url.deletingPathExtension().lastPathComponent
        return doc
    }

    override func makeUntitledDocument(ofType typeName: String) throws -> NSDocument {
        let doc = Sma4Document()
        doc.fileType = Sma4Document.smpType
        doc.loadNewProject()
        return doc
    }
}

extension Sma4Document {
    /// 新規(グラフ 1 枚・データなし)
    func loadNewProject() {
        var p = SMPProject()
        var g = AppSettings.shared.defaultGraph()
        g.name = "Untitled.SMP"
        p.graphs = [g]
        replaceProjectWithoutUndo(p)
    }

    func replaceProjectWithoutUndo(_ p: SMPProject) {
        preview { $0 = p }
        activeGraphIndex = 0
    }
}
