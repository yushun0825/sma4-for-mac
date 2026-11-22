# Sma4 for Mac

SMP ファイルを開いて、編集し、保存できる Mac のグラフ作成アプリです。
散布図を描き、最小二乗法やスプラインで曲線を当てはめられます。

## 入れ方

[Releases](https://github.com/yushun0825/sma4-for-mac/releases/latest) から `Sma4-for-Mac-<版>.dmg` をダウンロードして開き、
`Sma4 for Mac` を「Applications」(アプリケーション)フォルダへドラッグします。
macOS 14 以降(Apple シリコン・Intel)で動きます。

## 作り

- `Packages/Sma4Core` … SMP の読み書き(16bit 形式 ver. 1.5 の書き出しも)・数式変換・最小二乗法・スプライン・
  そのほかの解析(ガウス関数・ローレンツ関数での当てはめ、最大値・最小値・ピークを探す)・データマスク・目盛・目盛変換・
  文字の制御コード・マクロ・描画(Core Graphics)・PDF/PNG/EMF の書き出し。
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

## ないもの

- ほかのアプリとの DDE のやりとり、WMF の書き出し(EMF・PDF・PNG で書き出せます)、Gra-file の読み込み。

## ライセンス

MIT ライセンスです。[LICENSE](LICENSE) を見てください。
