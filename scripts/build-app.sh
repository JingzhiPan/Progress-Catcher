#!/bin/zsh
# 編譯並打包成 build/進度表.app。加 --install 會再複製一份到 /Applications。
# 這台機器沒有 Xcode，所以不走 xcodebuild：SwiftPM 編出執行檔，手動組成 .app，再做本機簽名。
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="0.3.1"
APP="build/進度表.app"

swift build -c release --product Jindu

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Jindu "$APP/Contents/MacOS/Jindu"
cp Assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>Jindu</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundleIdentifier</key><string>local.jindu.progress</string>
    <key>CFBundleName</key><string>進度表</string>
    <key>CFBundleDisplayName</key><string>進度表</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <!-- 只在菜單欄出現，不佔 Dock -->
    <key>LSUIElement</key><true/>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP"
echo "已打包：$APP"

if [[ "${1:-}" == "--install" ]]; then
  rm -rf "/Applications/進度表.app"
  cp -R "$APP" "/Applications/進度表.app"
  echo "已安裝到 /Applications/進度表.app"
fi
