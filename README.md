# Sma4 for Mac

SMP ファイルを開いて、編集し、保存できる Mac のグラフ作成アプリです。
散布図を描き、最小二乗法やスプラインで曲線を当てはめられます。

## 入れ方

[Releases](https://github.com/yushun0825/sma4-for-mac/releases/latest) から `Sma4-for-Mac-<版>.dmg` をダウンロードして開き、
`Sma4 for Mac` を「Applications」(アプリケーション)フォルダへドラッグします。
macOS 14 以降(Apple シリコン・Intel)で動きます。

## 作り

- `Packages/Sma4Core` … SMP の読み書き・数式変換・最小二乗法・スプライン・そのほかの解析(ガウス関数・ローレンツ関数での当てはめ、
  最大値・最小値・ピークを探す、なめらかにする)・データマスク・目盛・文字の制御コード・描画(Core Graphics)・PDF/PNG。
- `Sma4Mac/Win` … ダイアログの配置から Mac の部品を並べる仕組み(`DialogLayout`・`TemplateView`・`Dialog`・`PropertySheet`)。
- `Sma4Mac/Dialogs` … 各ダイアログの配置(`Layouts.swift`)と、部品と SMP の値をつなぐ処理。
- `Sma4Mac/Window`・`Sma4Mac/Canvas` … 主窓(ツールバー・作業面・ステータスバー)とマウスの操作。
  ツールバーの絵は `Sma4Mac/Window/ToolbarArt.swift`、アイコンは `Tools/make_icon.swift` で描いています。

## ビルド

`Tools/install.sh` で Release を作って `/Applications/Sma4 for Mac.app` に入れます。
配る DMG は `Tools/release.sh` で作ります(Developer ID の証明書と、Xcode にサインインした Apple アカウントが要ります)。

テスト:

```bash
cd Packages/Sma4Core && swift test
```

手元の SMP ファイルでも確かめるときは、そのフォルダを環境変数 `SMP_SAMPLE_DIR` に入れて実行します。

アプリの中の通しテスト(画面には出ません):

```bash
SMA4_TEST_INPUT="$PWD/Packages/Sma4Core/Tests/Sma4CoreTests/Fixtures/sweep_sjis.csv" SMA4_TEST_OUTPUT=/tmp/sma4-selftest \
  "build/DerivedData/Build/Products/Debug/Sma4 for Mac.app/Contents/MacOS/Sma4 for Mac" --selftest
```

## まだないもの・確かめていないもの

- ないもの: マクロ・DDE、Gra-file の読み込み、16 ビット版の形式での保存、メタファイル(WMF・EMF)の書き出し(PDF・PNG で代わり)。
- 押せないようにしてあるもの: ほかのグラフとつなぐ、目盛を式で変える、対数の 10⁰・10¹ を 1・10 と書く、
  %01N などの番号を表示しているデータだけで数える、枠と画像の位置を絶対値で決める。
- 保存はするが描き方にまだ反映していないもの: 文字の揃え(左・中央・右)、軸の交わる位置。
- 書き方を推し量っている SMP の項目: データマスク([MASKS])、図(種類 10)、そのほかの解析の系列(種類 8)、点の形 38〜52。

## ライセンス

MIT ライセンスです。[LICENSE](LICENSE) を見てください。
