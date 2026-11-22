import AppKit
import Sma4Core

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        _ = NSApplicationMain(CommandLine.argc, CommandLine.unsafeArgv)
    }

    func applicationWillFinishLaunching(_ notification: Notification) {
        // ツールバーの絵は黒い線なので、ダークモードでも明るい表示にする
        NSApp.appearance = NSAppearance(named: .aqua)
        // 最初に作った NSDocumentController が使われる
        _ = Sma4DocumentController()
        NSApp.mainMenu = MainMenuBuilder.build()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if SnapshotRunner.isActive {
            SnapshotRunner.run()
            return
        }
        if SelfTestRunner.isActive {
            SelfTestRunner.run()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { !SnapshotRunner.isActive && !SelfTestRunner.isActive }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }

    func applicationDidBecomeActive(_ notification: Notification) {
        // エディタで直したデータファイルを読み直す
        for doc in NSDocumentController.shared.documents.compactMap({ $0 as? Sma4Document }) {
            doc.reloadChangedDataFiles(force: false)
        }
    }

    var keyWindow: NSWindow? { NSApp.keyWindow ?? NSApp.mainWindow }

    @objc func showAbout(_ sender: Any?) { MiscDialogs.about(over: keyWindow) }

    @objc func showSettings(_ sender: Any?) { MiscDialogs.settings(over: keyWindow) }

    @objc func showHelp(_ sender: Any?) { HelpWindow.show(topic: .top) }
}
