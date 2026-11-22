import AppKit
import Sma4Core

/// メニュー。
@MainActor
enum MainMenuBuilder {
    typealias W = GraphWindowController
    typealias A = AppDelegate

    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(appMenu())
        main.addItem(fileMenu())
        main.addItem(dataMenu())
        main.addItem(editMenu())
        main.addItem(graphMenu())
        main.addItem(insertMenu())
        main.addItem(analysisMenu())
        main.addItem(otherMenu())
        let help = helpMenu()
        main.addItem(help)
        NSApp.helpMenu = help.submenu
        return main
    }

    static func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = [.command], tag: Int = 0) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.keyEquivalentModifierMask = key.isEmpty ? [] : mods
        i.tag = tag
        return i
    }

    static func submenu(_ title: String, _ items: [NSMenuItem], delegate: NSMenuDelegate? = nil) -> NSMenuItem {
        let top = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let m = NSMenu(title: title)
        m.autoenablesItems = true
        items.forEach { m.addItem($0) }
        m.delegate = delegate
        top.submenu = m
        return top
    }

    static func fKey(_ n: Int) -> String {
        String(Character(UnicodeScalar(NSF1FunctionKey + n - 1)!))
    }

    static func appMenu() -> NSMenuItem {
        let name = "Sma4 for Mac"
        let services = NSMenuItem(title: "サービス", action: nil, keyEquivalent: "")
        let sm = NSMenu(title: "サービス")
        services.submenu = sm
        NSApp.servicesMenu = sm
        return submenu(name, [
            item("\(name) について", #selector(A.showAbout(_:))),
            .separator(),
            item("設定…", #selector(A.showSettings(_:)), ","),
            .separator(),
            services,
            .separator(),
            item("\(name) を隠す", #selector(NSApplication.hide(_:)), "h"),
            item("ほかを隠す", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("すべてを表示", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("\(name) を終了", #selector(NSApplication.terminate(_:)), "q"),
        ])
    }

    static func fileMenu() -> NSMenuItem {
        submenu("ファイル", [
            item("新しいグラフを加える", #selector(W.addGraph(_:)), "n"),
            item("グラフを削除", #selector(W.deleteGraph(_:)), "d", [.command, .shift]),
            item("すべてのグラフを削除", #selector(W.deleteAllGraphs(_:))),
            .separator(),
            item("グラフを開く…", #selector(W.importGraphs(_:))),
            item("保存", #selector(W.saveGraphs(_:)), "s"),
            item("選んだグラフだけ保存…", #selector(W.saveActiveGraph(_:))),
            item("別名ですべて保存…", #selector(W.saveAllAs(_:)), "j"),
            .separator(),
            item("既定のグラフとして保存", #selector(W.saveAsDefault(_:))),
            item("ひな形を選ぶ…", #selector(W.chooseTemplate(_:))),
            .separator(),
            item("印刷…", #selector(W.printGraphs(_:)), "p"),
            item("ページ設定…", #selector(W.printerSetup(_:))),
            item("印刷の大きさ…", #selector(W.paperSetup(_:))),
            item("プレビュー", #selector(W.togglePreview(_:)), "r"),
            .separator(),
            submenu("書き出す", [
                item("PDF…", #selector(W.exportPDF(_:))),
                item("PNG…", #selector(W.exportPNG(_:))),
            ]),
            item("閉じる", #selector(W.closeWindow(_:)), "w"),
            .separator(),
            item("終了", #selector(W.quitAll(_:))),
            .separator(),
        ], delegate: RecentFilesMenu.shared)
    }

    static func dataMenu() -> NSMenuItem {
        submenu("データ", [
            item("データを開く…", #selector(W.openDataFile(_:)), "o"),
            item("データを閉じる", #selector(W.closeDataFile(_:))),
            .separator(),
            item("新しいデータファイル…", #selector(W.createDataFile(_:))),
            .separator(),
            item("データの設定…", #selector(W.showDataManager(_:)), "u"),
            .separator(),
            item("表示する・隠す", #selector(W.toggleSeriesVisibility(_:))),
            .separator(),
            item("エディタで編集", #selector(W.editDataFile(_:)), "e", [.command, .shift]),
            .separator(),
            item("データを保存…", #selector(W.saveData(_:))),
            item("値を読む", #selector(W.toggleReadValue(_:)), fKey(4), []),
            item("データマスク…", #selector(W.dataMask(_:))),
        ])
    }

    static func editMenu() -> NSMenuItem {
        submenu("編集", [
            item("図としてコピー", #selector(W.copy(_:)), "c"),
            item("データをコピー", #selector(W.copyData(_:))),
            .separator(),
            item("データを貼り付け", #selector(W.pasteData(_:))),
            .separator(),
            item("取り消す", #selector(W.undoAction(_:)), "z"),
            item("オブジェクトをカット", #selector(W.cutObject(_:))),
            item("オブジェクトをコピー", #selector(W.copyObject(_:))),
            item("ペースト", #selector(W.paste(_:)), "v"),
            item("削除", #selector(W.delete(_:))),
        ])
    }

    static func graphMenu() -> NSMenuItem {
        submenu("グラフ", [
            item("X 軸…", #selector(W.showAxisDialog(_:)), "x", tag: 0),
            item("Y 軸…", #selector(W.showAxisDialog(_:)), "y", tag: 1),
            item("U 軸…", #selector(W.showAxisDialog(_:)), tag: 2),
            item("R 軸…", #selector(W.showAxisDialog(_:)), tag: 3),
            item("すべての軸の範囲を戻す", #selector(W.clearAllScale(_:))),
            submenu("軸の範囲を戻す", [
                item("X 軸", #selector(W.clearScale(_:)), tag: 0),
                item("Y 軸", #selector(W.clearScale(_:)), tag: 1),
                item("U 軸", #selector(W.clearScale(_:)), tag: 2),
                item("R 軸", #selector(W.clearScale(_:)), tag: 3),
            ]),
            .separator(),
            item("範囲を決めて拡大", #selector(W.beginTrimming(_:))),
            .separator(),
            item("枠…", #selector(W.showFrameDialog(_:)), "f"),
            .separator(),
            item("グラフの設定…", #selector(W.showGraphProperty(_:))),
            .separator(),
            item("すべてのグラフを表示", #selector(W.showAllGraphs(_:))),
            item("選んだグラフだけ表示", #selector(W.showActiveGraphOnly(_:))),
            .separator(),
        ], delegate: GraphListMenu.shared)
    }

    static func insertMenu() -> NSMenuItem {
        submenu("挿入", [
            item("X 軸の題", #selector(W.insertTitle(_:)), "x", [.command, .shift], tag: 4),
            item("Y 軸の題", #selector(W.insertTitle(_:)), "y", [.command, .shift], tag: 5),
            item("U 軸の題", #selector(W.insertTitle(_:)), tag: 6),
            item("R 軸の題", #selector(W.insertTitle(_:)), tag: 7),
            item("文字", #selector(W.insertTitle(_:)), "o", [.command, .shift], tag: 8),
            item("クリップボードの文字", #selector(W.pasteTextFromClipboard(_:))),
            item("凡例", #selector(W.insertLegend(_:))),
            submenu("文字を揃える", [
                item("左", #selector(W.alignTexts(_:)), tag: 0),
                item("中央", #selector(W.alignTexts(_:)), tag: 1),
                item("右", #selector(W.alignTexts(_:)), tag: 2),
            ]),
            .separator(),
            item("矢印", #selector(W.insertArrow(_:)), "a", [.command, .shift]),
            item("点", #selector(W.insertDot(_:))),
            item("枠", #selector(W.insertBox(_:))),
            .separator(),
            item("画像…", #selector(W.insertPicture(_:))),
            .separator(),
            item("重なりの順番…", #selector(W.reorderObjects(_:))),
        ])
    }

    static func analysisMenu() -> NSMenuItem {
        var special: [NSMenuItem] = [item("そのほかの解析について", #selector(W.aboutDLL(_:))), .separator()]
        for (k, a) in ExtensionAnalysis.allCases.enumerated() {
            special.append(item(a.menuTitle, #selector(W.extensionAnalysis(_:)), tag: k))
        }
        return submenu("解析", [
            submenu("最小二乗法", [
                item("多項式", #selector(W.leastSquares(_:)), "b", tag: 1),
                item("指数関数", #selector(W.leastSquares(_:)), tag: 4),
                item("対数関数", #selector(W.leastSquares(_:)), tag: 5),
                item("べき関数", #selector(W.leastSquares(_:)), tag: 6),
                item("一般の関数", #selector(W.leastSquares(_:)), "d", tag: 7),
                .separator(),
                item("値を求める", #selector(W.evaluateFit(_:)), fKey(5), []),
            ]),
            submenu("スプライン", [
                item("3 次スプライン", #selector(W.spline(_:)), "e", tag: 0),
                item("パラメトリック", #selector(W.spline(_:)), tag: 1),
                item("パラメトリック(閉じた曲線)", #selector(W.spline(_:)), tag: 2),
            ]),
            submenu("そのほかの解析", special),
            item("解析をやり直す", #selector(W.reanalyze(_:)), "a"),
            item("解析を消す", #selector(W.clearAnalysis(_:))),
            .separator(),
            item("関数を描く…", #selector(W.drawFunction(_:))),
            item("定数…", #selector(W.showConstants(_:)), "g"),
            .separator(),
            item("曲線のデータをコピー", #selector(W.copyCurveData(_:))),
        ])
    }

    static func otherMenu() -> NSMenuItem {
        submenu("ツール", [
            item("設定…", #selector(A.showSettings(_:))),
            .separator(),
            item("計算機", #selector(W.showCalculator(_:)), fKey(3), []),
        ])
    }

    static func helpMenu() -> NSMenuItem {
        submenu("ヘルプ", [
            item("Sma4 for Mac ヘルプ", #selector(A.showHelp(_:)), fKey(1), []),
            .separator(),
            item("Sma4 for Mac について", #selector(A.showAbout(_:))),
        ])
    }
}

/// ファイル メニューの下の、最近使ったファイル
@MainActor
final class RecentFilesMenu: NSObject, NSMenuDelegate {
    static let shared = RecentFilesMenu()
    static let tag = 9100

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.filter { $0.tag >= RecentFilesMenu.tag }.forEach(menu.removeItem)
        for (k, path) in AppSettings.shared.recentFiles.enumerated() {
            let i = NSMenuItem(title: "\(k + 1):\((path as NSString).lastPathComponent)", action: #selector(GraphWindowController.openRecent(_:)), keyEquivalent: "")
            i.tag = RecentFilesMenu.tag + k
            i.representedObject = path
            i.toolTip = path
            menu.addItem(i)
        }
    }
}

/// グラフ メニューの下の、グラフの一覧(選んだものが選択中のグラフになる)
@MainActor
final class GraphListMenu: NSObject, NSMenuDelegate {
    static let shared = GraphListMenu()
    static let tagBase = 9200

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.items.filter { $0.representedObject as? String == "graph" }.forEach(menu.removeItem)
        guard let doc = (NSApp.mainWindow?.windowController as? GraphWindowController)?.doc else { return }
        for (k, g) in doc.project.graphs.enumerated() {
            let i = NSMenuItem(title: "\(k + 1):\(g.name)", action: #selector(GraphWindowController.selectGraph(_:)), keyEquivalent: "")
            i.tag = k
            i.representedObject = "graph"
            menu.addItem(i)
        }
    }
}
