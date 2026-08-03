#!/bin/bash
# NetDiagnose 一键打包：编译 release → 组装 .app → ad-hoc 签名 → 生成 .dmg
set -euo pipefail
cd "$(dirname "$0")"

VERSION="1.1"
APP_NAME="NetDiagnose"
SRC_BIN=".build/release/$APP_NAME"
DIST_DIR="dist"

echo "▶ 编译 release..."
swift build -c release

echo "▶ 组装 $APP_NAME.app..."
rm -rf "$DIST_DIR/$APP_NAME.app"
mkdir -p "$DIST_DIR/$APP_NAME.app/Contents/MacOS"
mkdir -p "$DIST_DIR/$APP_NAME.app/Contents/Resources"
cp "$SRC_BIN" "$DIST_DIR/$APP_NAME.app/Contents/MacOS/$APP_NAME"
cp "Packaging/Info.plist" "$DIST_DIR/$APP_NAME.app/Contents/Info.plist"
if [ -f "Packaging/AppIcon.icns" ]; then
    cp "Packaging/AppIcon.icns" "$DIST_DIR/$APP_NAME.app/Contents/Resources/AppIcon.icns"
fi

echo "▶ 签名 (ad-hoc)..."
codesign --force --deep -s - "$DIST_DIR/$APP_NAME.app"

echo "▶ 创建 DMG..."
rm -f "$DIST_DIR/${APP_NAME}_v${VERSION}.dmg"
hdiutil create -volname "$APP_NAME" -srcfolder "$DIST_DIR/$APP_NAME.app" -ov -format UDZO "$DIST_DIR/${APP_NAME}_v${VERSION}.dmg"

echo "✅ 完成：$DIST_DIR/${APP_NAME}_v${VERSION}.dmg"
