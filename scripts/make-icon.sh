#!/bin/zsh
# 產生 app 圖標：Assets/icon.svg → 各尺寸 PNG → Assets/AppIcon.icns
# （重新畫的時候也會更新菜單欄剪影 Sources/Jindu/MenuBarGlyph.swift）
#
# 圖是 scripts/icon/inchworm.py 畫的（一隻拱起來的毛毛蟲）。它依賴 flat-creature 技能裡的生成器，
# 那個不在倉庫裡；設了 FLAT_CREATURE_SCRIPTS 就會重新畫，沒設就直接用倉庫裡現成的 Assets/icon.svg。
# 傳給這個腳本的參數會原樣交給 inchworm.py，例如：
#   ./scripts/make-icon.sh --palette catcher --plate "#F7F6F3"
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ -n "${FLAT_CREATURE_SCRIPTS:-}" ]]; then
  python3 scripts/icon/inchworm.py --out-dir Assets --swift-out Sources/Jindu/MenuBarGlyph.swift "$@"
  rm -f Assets/inchworm.svg
fi

mkdir -p .build
swiftc -O scripts/icon/svg2png.swift -o .build/svg2png

SET=.build/AppIcon.iconset
rm -rf "$SET" && mkdir -p "$SET"
for size in 16 32 128 256 512; do
  .build/svg2png Assets/icon.svg "$SET/icon_${size}x${size}.png" $size
  .build/svg2png Assets/icon.svg "$SET/icon_${size}x${size}@2x.png" $((size * 2))
done
iconutil -c icns "$SET" -o Assets/AppIcon.icns
echo "已產生 Assets/AppIcon.icns"
