#!/bin/bash
# Release でビルドして /Applications に入れる(アプリを消してから置き直さない: ditto で上書きする)
set -euo pipefail
cd "$(dirname "$0")/.."
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
APP_NAME="Sma4 for Mac"
xcodegen generate --quiet
xcodebuild -project Sma4Mac.xcodeproj -scheme Sma4Mac -configuration Release \
  -derivedDataPath build/DerivedData -destination 'platform=macOS' build -quiet
SRC="build/DerivedData/Build/Products/Release/$APP_NAME.app"
DEST="/Applications/$APP_NAME.app"
if pgrep -xq "$APP_NAME"; then
  echo "$APP_NAME が起動中です。終了してからもう一度実行してください。" >&2
  exit 1
fi
# アプリ自体は消さずに中身だけを入れ替える(前の版にしか無いファイルは消して、署名が崩れないようにする)
if [ -d "$DEST" ]; then
  rsync -a --delete "$SRC/" "$DEST/"
else
  ditto "$SRC" "$DEST"
fi
codesign -v --deep --strict "$DEST"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$DEST"
echo "入れました: $DEST"
