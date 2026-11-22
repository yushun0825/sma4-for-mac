import AppKit

/// ヘルプ(使い方と、文字列の書き方の早見表)
@MainActor
enum HelpWindow {
    enum Topic { case top, text }

    private static var window: NSWindow?
    private static var textView: NSTextView?

    static func show(topic: Topic) {
        if window == nil {
            let w = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 620, height: 640), styleMask: [.titled, .closable, .resizable, .utilityWindow],
                            backing: .buffered, defer: true)
            w.title = "Sma4 for Mac ヘルプ"
            w.isReleasedWhenClosed = false
            w.worksWhenModal = true
            w.hidesOnDeactivate = false
            let sv = NSTextView.scrollableTextView()
            if let tv = sv.documentView as? NSTextView {
                tv.isEditable = false
                tv.textContainerInset = NSSize(width: 14, height: 14)
                tv.textStorage?.setAttributedString(content())
                textView = tv
            }
            w.contentView = sv
            w.center()
            window = w
        }
        window?.makeKeyAndOrderFront(nil)
        if topic == .text, let tv = textView, let r = tv.string.range(of: "文字列の書き方") {
            let ns = NSRange(r, in: tv.string)
            tv.scrollRangeToVisible(ns)
            tv.showFindIndicator(for: ns)
        }
    }

    static let sections: [(String, String)] = [
        ("Sma4 for Mac について", """
        SMP ファイルを開いて、編集し、保存できるグラフ作成アプリです。SMP ファイルは Shift_JIS・CRLF・ver. 1.8 の形で保存します。
        おもなショートカットは ⌘X で X 軸、⌘S で保存です。F キーは F1 ヘルプ・F2 描き直す・F3 計算機・F4 値を読む・F5 値を求める です。
        """),
        ("マウスの操作", """
        ・グラフの大きさは、グラフの右下の角などを左ボタンでドラッグして変えます。グラフ全体を動かすには、U 軸(上の辺)をドラッグします。
        ・文字・点・矢印・枠は、左ボタンでドラッグして動かします。矢印は、端を持つともう一方の端を支点に長さが変わり、真ん中を持つと全体が動きます。
        ・ダブルクリックで設定の画面が出ます(軸のあたりなら軸、枠なら枠、グラフの中ならデータ)。
        ・右ボタンで範囲を囲むと「この範囲をコピー・この範囲を PDF で保存・この範囲に拡大・この範囲をマスク」のメニューが出ます。右クリックでグラフを選び、そのグラフのメニューを出します。
        ・「値を読む」の間は、ホイールや ← → で点を動かせます。
        ・新しい文字は、ダイアログの OK のあと、マウスの所に出る枠をクリックした位置(文字の開始の左下)に置きます。矢印・枠は「マウスで置く」のあと、始点から終点までドラッグします。
        """),
        ("文字列の書き方", """
        ^…@  上付き(例: 10^3@ で 10³)        _…@  下付き
        \\n  改行(エディットボックスの中で改行してもよい)        %W???  改行幅(1/10 mm)
        %R ローマン体  %I イタリック  %B ボールド  %O ボールドイタリック
        %U…%U 下線   %L…%L 上線
        %Sxyz 文字の大きさを xyz %に   %X±xy・%Y±xy 左右・上下にずらす(文字の高さの %)
        %G…%A  ギリシャ文字(Symbol)。例: %Gm%A → μ、%GD%A → Δ
        %Q???  文字コード(例: %Q197 → Å、%Q176 → °)
        %K??????  色(16 進の RRGGBB。例: %KFF0000 で赤)
        %J名前%J  フォントの切り替え
        %??N・%??n データファイル名   %??E データのプロットタイプ   %??F スプラインや最小二乗曲線の線種
        %??D・%??T データファイルの日付・時刻   %??Cxxyy ファイルの xx 行の yy 列(yy=00 は行全体)
        %N・%n SMP のファイル名   %D・%T SMP の日付・時刻   %M・%V 今日の日付・時刻   %H??? %E・%F の長さ
        (?? はファイルの番号 01〜、00 は最初に描くファイル)
        """),
        ("数式変換", """
        変数 x・y、定数 a〜i(解析 → 定数…)、pi が使えます。演算子は + - * / ^。
        関数: abs sqrt exp ln log sin cos tan asin acos atan sinh cosh tanh dif integ theta delta erfc max min pow gamma beta
        #0003 は自分のデータの 3 列目、#0203 は 2 番目に描くデータの 3 列目です。
        欠損データは = か | で書きます(= はエラー値として線を切り、| は読み飛ばします)。
        """),
        ("図としてコピー・書き出す", """
        編集 → 図としてコピー(⌘C)で、コピー領域を確かめてから、PDF(拡大しても荒れない形)と PNG をクリップボードに入れます。Word・PowerPoint・Keynote に貼り付けられます。
        ファイル → 書き出す で PDF・PNG・EMF(拡張メタファイル)を書き出せます。EMF は Office などに線と面の図として貼れます(文字は輪郭の図形になり、図の画像は入りません)。
        """),
        ("保存の形", """
        ふだんは ver. 1.8 の形で保存します。保存の窓の下の「16 ビット版の形式で保存する」を選ぶと、その保存のときだけ ver. 1.5 の形で書きます(目盛変換など ver. 1.5 に無い設定は書きません)。
        """),
        ("マクロ", """
        ツール → マクロを実行…(⌥⌘M)で、マクロのファイル(.smd)を上から 1 行ずつ実行します。
        使える命令: FrameSet(POS・FRAMETYPE・LINEWIDTH・COLOR)・AxisSet(XSCALE〜RSCALE・XSCALETYPE〜RSCALETYPE・COLOR)・Data(COLUMNX・COLUMNY・PLOTTYPE・PLOTSIZE・COLOR・LINETYPE・LINECOLOR・LINEWIDTH・LINEPITCH・XTRANS・YTRANS・Open)・Insert(XTITLE・YTITLE)・Rem・Label・Goto・Pause・Print・DeleteGraph・OpenSmp・Refresh。
        読めない行があると、その行の番号を出して止まります。
        """),
    ]

    static func content() -> NSAttributedString {
        let out = NSMutableAttributedString()
        let head: [NSAttributedString.Key: Any] = [.font: NSFont.boldSystemFont(ofSize: 14), .foregroundColor: NSColor.labelColor]
        let body: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 12), .foregroundColor: NSColor.labelColor]
        for (k, (title, text)) in sections.enumerated() {
            out.append(NSAttributedString(string: (k > 0 ? "\n" : "") + title + "\n", attributes: head))
            out.append(NSAttributedString(string: text + "\n", attributes: body))
        }
        return out
    }
}
