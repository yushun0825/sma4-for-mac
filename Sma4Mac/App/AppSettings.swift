import AppKit
import Combine
import Sma4Core

/// 「ツール → 設定」と、各ダイアログの「既定にする」で覚える値。UserDefaults に保存する。
/// 項目は設定の画面(ファイル・表示)と同じ。
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    private let d = UserDefaults.standard

    // file
    @Published var saveDataWithGraph: Bool { didSet { d.set(saveDataWithGraph, forKey: "saveDataWithGraph") } }
    @Published var omitPathInSameFolder: Bool { didSet { d.set(omitPathInSameFolder, forKey: "omitPathInSameFolder") } }
    @Published var preferEmbeddedData: Bool { didSet { d.set(preferEmbeddedData, forKey: "preferEmbeddedData") } }
    @Published var textSMP: Bool { didSet { d.set(textSMP, forKey: "textSMP") } }
    @Published var wildcard: String { didSet { d.set(wildcard, forKey: "wildcard") } }
    @Published var editorPath: String { didSet { d.set(editorPath, forKey: "editorPath") } }
    @Published var propertiesOnLaunchOpen: Bool { didSet { d.set(propertiesOnLaunchOpen, forKey: "propertiesOnLaunchOpen") } }
    @Published var autoDotType: Bool { didSet { d.set(autoDotType, forKey: "autoDotType") } }
    @Published var autoLineType: Bool { didSet { d.set(autoLineType, forKey: "autoLineType") } }
    @Published var autoDotColor: Bool { didSet { d.set(autoDotColor, forKey: "autoDotColor") } }
    @Published var autoLineColor: Bool { didSet { d.set(autoLineColor, forKey: "autoLineColor") } }
    @Published var autoScaleX: Bool { didSet { d.set(autoScaleX, forKey: "autoScaleX") } }
    @Published var autoScaleY: Bool { didSet { d.set(autoScaleY, forKey: "autoScaleY") } }

    // etc.
    @Published var clipToFrame: Bool { didSet { d.set(clipToFrame, forKey: "clipToFrame"); changed() } }
    @Published var showToolbar: Bool { didSet { d.set(showToolbar, forKey: "showToolbar"); changed() } }
    @Published var showStatusBar: Bool { didSet { d.set(showStatusBar, forKey: "showStatusBar"); changed() } }
    @Published var printBackground: Bool { didSet { d.set(printBackground, forKey: "printBackground") } }
    @Published var readValueSort: Bool { didSet { d.set(readValueSort, forKey: "readValueSort") } }
    @Published var trimmingSort: Bool { didSet { d.set(trimmingSort, forKey: "trimmingSort") } }
    /// スナップ(mm、0 はしない)
    @Published var snapMM: Double { didSet { d.set(snapMM, forKey: "snapMM2") } }
    /// グリッド表示(mm、0 は表示しない)
    @Published var gridMM: Double { didSet { d.set(gridMM, forKey: "gridMM2"); changed() } }
    @Published var gridColor: SMPColor { didSet { d.set(gridColor.colorref, forKey: "gridColor"); changed() } }
    @Published var backgroundColor: SMPColor { didSet { d.set(backgroundColor.colorref, forKey: "backgroundColor"); changed() } }
    @Published var readValueColor: SMPColor { didSet { d.set(readValueColor.colorref, forKey: "readValueColor"); changed() } }
    /// 表示サイズ(%)
    @Published var screenSize: Double { didSet { d.set(screenSize, forKey: "screenSize"); changed() } }
    @Published var superscriptScale: Double { didSet { d.set(superscriptScale, forKey: "superscriptScale2"); changed() } }
    @Published var superscriptRise: Double { didSet { d.set(superscriptRise, forKey: "superscriptRise2"); changed() } }
    @Published var subscriptDrop: Double { didSet { d.set(subscriptDrop, forKey: "subscriptDrop2"); changed() } }
    @Published var printFooter: Bool { didSet { d.set(printFooter, forKey: "printFooter") } }

    // 図面コピーの領域(SET_CLIPRGN)
    @Published var copyMargins: [Double] { didSet { d.set(copyMargins, forKey: "copyMargins") } }
    @Published var copyScale: Double { didSet { d.set(copyScale, forKey: "copyScale") } }
    @Published var exportDPI: Double { didSet { d.set(exportDPI, forKey: "exportDPI") } }
    /// Save Data の区切り(TAB か コンマ)
    @Published var exportSeparatorTab: Bool { didSet { d.set(exportSeparatorTab, forKey: "exportSeparatorTab") } }

    static let settingsChanged = Notification.Name("Sma4SettingsChanged")

    private init() {
        d.register(defaults: [
            "saveDataWithGraph": true, "omitPathInSameFolder": false, "preferEmbeddedData": false, "textSMP": true,
            "wildcard": "*.*", "editorPath": "", "propertiesOnLaunchOpen": true,
            "autoDotType": true, "autoLineType": false, "autoDotColor": false, "autoLineColor": false,
            "autoScaleX": true, "autoScaleY": true,
            "clipToFrame": false, "showToolbar": true, "showStatusBar": true, "printBackground": false,
            "readValueSort": true, "trimmingSort": true, "snapMM2": 1.0, "gridMM2": 0.0,
            "gridColor": 0xC0C0C0, "backgroundColor": 0xFFFFFF, "readValueColor": 0x00FF00, "screenSize": 70.0,
            "superscriptScale2": 70.0, "superscriptRise2": 50.0, "subscriptDrop2": 20.0, "printFooter": false,
            "copyMargins": [10.0, 10.0, 10.0, 10.0], "copyScale": 100.0, "exportDPI": 300.0, "exportSeparatorTab": true,
        ])
        saveDataWithGraph = d.bool(forKey: "saveDataWithGraph")
        omitPathInSameFolder = d.bool(forKey: "omitPathInSameFolder")
        preferEmbeddedData = d.bool(forKey: "preferEmbeddedData")
        textSMP = d.bool(forKey: "textSMP")
        wildcard = d.string(forKey: "wildcard") ?? "*.*"
        editorPath = d.string(forKey: "editorPath") ?? ""
        propertiesOnLaunchOpen = d.bool(forKey: "propertiesOnLaunchOpen")
        autoDotType = d.bool(forKey: "autoDotType")
        autoLineType = d.bool(forKey: "autoLineType")
        autoDotColor = d.bool(forKey: "autoDotColor")
        autoLineColor = d.bool(forKey: "autoLineColor")
        autoScaleX = d.bool(forKey: "autoScaleX")
        autoScaleY = d.bool(forKey: "autoScaleY")
        clipToFrame = d.bool(forKey: "clipToFrame")
        showToolbar = d.bool(forKey: "showToolbar")
        showStatusBar = d.bool(forKey: "showStatusBar")
        printBackground = d.bool(forKey: "printBackground")
        readValueSort = d.bool(forKey: "readValueSort")
        trimmingSort = d.bool(forKey: "trimmingSort")
        snapMM = d.double(forKey: "snapMM2")
        gridMM = d.double(forKey: "gridMM2")
        gridColor = SMPColor(colorref: d.integer(forKey: "gridColor"))
        backgroundColor = SMPColor(colorref: d.integer(forKey: "backgroundColor"))
        readValueColor = SMPColor(colorref: d.integer(forKey: "readValueColor"))
        screenSize = d.double(forKey: "screenSize")
        superscriptScale = d.double(forKey: "superscriptScale2")
        superscriptRise = d.double(forKey: "superscriptRise2")
        subscriptDrop = d.double(forKey: "subscriptDrop2")
        printFooter = d.bool(forKey: "printFooter")
        copyMargins = (d.array(forKey: "copyMargins") as? [Double]) ?? [10, 10, 10, 10]
        copyScale = d.double(forKey: "copyScale")
        exportDPI = d.double(forKey: "exportDPI")
        exportSeparatorTab = d.bool(forKey: "exportSeparatorTab")
    }

    private func changed() {
        NotificationCenter.default.post(name: AppSettings.settingsChanged, object: nil)
    }

    var dataOpenPreferences: DataOpenPreferences {
        var p = DataOpenPreferences()
        p.autoDotType = autoDotType
        p.autoLineType = autoLineType
        p.autoDotColor = autoDotColor
        p.autoLineColor = autoLineColor
        p.autoScaleX = autoScaleX
        p.autoScaleY = autoScaleY
        return p
    }

    func renderOptions(fileName: String, fileDate: Date) -> RenderOptions {
        var o = RenderOptions()
        o.clipToFrame = clipToFrame
        o.superscriptScale = superscriptScale / 100
        o.superscriptRise = superscriptRise / 100
        o.subscriptDrop = subscriptDrop / 100
        o.fileName = fileName
        o.fileDate = fileDate
        return o
    }

    // MARK: - 既定のグラフ(Save as default・テンプレートの設定)

    static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Sma4 for Mac", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var defaultGraphURL: URL { supportDirectory.appendingPathComponent("default.SMP") }

    /// テンプレートに選んだ SMP の場所(なければ Save as default の既定)
    var templatePath: String? {
        get { d.string(forKey: "templatePath") }
        set { d.set(newValue, forKey: "templatePath") }
    }

    /// 新しいグラフの元(ひな形 → 既定のグラフとして保存したもの → 既定 の順)
    func defaultGraph() -> Graph {
        var urls: [URL] = []
        if let t = templatePath { urls.append(URL(fileURLWithPath: t)) }
        urls.append(AppSettings.defaultGraphURL)
        for url in urls {
            if let data = try? Data(contentsOf: url), let p = try? SMPReader.read(data: data), var g = p.graphs.first {
                g.series = []
                g.masks = []
                g.id = UUID()
                g.objects = g.objects.map { ObjectItem($0.object) }
                return g
            }
        }
        return Graph.makeDefault()
    }

    func saveAsDefault(_ graph: Graph) throws {
        var p = SMPProject()
        var g = graph
        g.series = []
        g.masks = []
        g.page.saveData = false
        p.graphs = [g]
        try SMPWriter.data(for: p).write(to: AppSettings.defaultGraphURL)
    }

    // MARK: - ダイアログの「保存」で覚える値

    func stored<T: Codable>(_ key: String, as type: T.Type) -> T? {
        guard let data = d.data(forKey: "ini." + key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    func store<T: Codable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { d.set(data, forKey: "ini." + key) }
    }

    // MARK: - 最近使ったファイル

    var recentFiles: [String] {
        get { d.stringArray(forKey: "recentFiles") ?? [] }
        set { d.set(Array(newValue.prefix(4)), forKey: "recentFiles") }
    }

    func noteRecent(_ path: String) {
        // 確認用の起動(--snapshot・--selftest)では記録しない
        if SnapshotRunner.isActive || SelfTestRunner.isActive { return }
        var r = recentFiles.filter { $0 != path }
        r.insert(path, at: 0)
        recentFiles = r
    }
}
