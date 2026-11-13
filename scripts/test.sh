#!/bin/zsh
# 跑核心邏輯測試。
# 這台機器只有 Command Line Tools（沒有 Xcode），Testing 框架不在預設搜尋路徑上，所以要手動指過去。
set -euo pipefail
cd "$(dirname "$0")/.."

CLT=/Library/Developer/CommandLineTools
FW=$CLT/Library/Developer/Frameworks

swift test \
  -Xswiftc -F -Xswiftc "$FW" \
  -Xswiftc -plugin-path -Xswiftc "$CLT/usr/lib/swift/host/plugins/testing" \
  -Xlinker -F -Xlinker "$FW" \
  -Xlinker -rpath -Xlinker "$FW" \
  -Xlinker -rpath -Xlinker "$CLT/Library/Developer/usr/lib" \
  "$@"
