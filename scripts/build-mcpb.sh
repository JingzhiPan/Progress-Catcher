#!/bin/zsh
# 把 MCP 服務打包成 build/Progress-Catcher.mcpb：一個檔案，用 Claude 桌面版打開就會跳出安裝視窗。
# .mcpb 其實就是 zip：manifest.json（說明這是什麼、怎麼啟動）+ 可執行檔 + 圖標。
set -euo pipefail
cd "$(dirname "$0")/.."

OUT="build/Progress-Catcher.mcpb"
STAGE=".build/mcpb"

swift build -c release --product JinduMCP

rm -rf "$STAGE" "$OUT"
mkdir -p "$STAGE/server" build
cp .build/release/JinduMCP "$STAGE/server/progress-catcher-mcp"
chmod 755 "$STAGE/server/progress-catcher-mcp"
codesign --force --sign - "$STAGE/server/progress-catcher-mcp" 2>/dev/null

# 圖標：直接從 app 圖標縮一張
sips -s format png -Z 256 Assets/AppIcon.icns --out "$STAGE/icon.png" >/dev/null

# 工具清單和版本號問執行檔自己要，manifest 不另外手抄一份
"$STAGE/server/progress-catcher-mcp" --list-tools | python3 -c '
import json, sys
info = json.load(sys.stdin)
manifest = {
    "manifest_version": "0.3",
    "name": "progress-catcher",
    "display_name": "Progress Catcher 進度表",
    "version": info["version"],
    "description": "Let Claude lay out and update your Progress Catcher tracker: projects, numbered grids, checklists, recurring tasks and deadlines.",
    "long_description": "Works with the Progress Catcher menu bar app on this Mac. Claude can read your progress, create projects, add numbered grids, checklists and recurring tasks, set deadlines, and mark things done. Everything stays in a local file on this Mac; nothing is sent anywhere. Changes show up in the menu bar panel immediately. There are no delete tools.",
    "author": {"name": "Jin", "url": "https://github.com/JingzhiPan"},
    "homepage": "https://github.com/JingzhiPan/Progress-Catcher",
    "icon": "icon.png",
    "server": {
        "type": "binary",
        "entry_point": "server/progress-catcher-mcp",
        "mcp_config": {"command": "${__dirname}/server/progress-catcher-mcp", "args": [], "env": {}},
    },
    "tools": info["tools"],
    "keywords": ["progress", "tracker", "habits", "deadline", "menu bar"],
    "compatibility": {"platforms": ["darwin"]},
}
json.dump(manifest, sys.stdout, ensure_ascii=False, indent=2)
' > "$STAGE/manifest.json"

(cd "$STAGE" && zip -q -r -X -9 "../../$OUT" manifest.json icon.png server)
echo "已打包：$OUT（$(du -h "$OUT" | cut -f1 | tr -d ' ')）"
