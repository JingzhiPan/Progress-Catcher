# 進度表

Mac 菜單欄上的進度跟進小工具：一段編號逐格蓋章，或一張清單逐項勾掉。可置頂浮在最上層，也可收成迷你條。

## 用法

- 點菜單欄圖標打開面板；右鍵圖標有「設定」和「退出」。
- 首頁是所有項目的進度，最近做過的排最前。點進項目後加分組：**編號格子**（填起止數字）或**清單**。
- 格子：點一下蓋章，再點取消；按住拖過去連續蓋。
- 圖釘：置頂。置頂後多一個按鈕可收成迷你條，只顯示正在做的那一組。
- 資料在 `~/Library/Application Support/Jindu/data.json`，每天自動備份到旁邊的 `backups/`。

## 開發

這台機器只有 Command Line Tools，沒有 Xcode，所以全程用 SwiftPM 加腳本。

```bash
./scripts/test.sh                  # 核心邏輯測試
./scripts/build-app.sh             # 打包成 build/進度表.app
./scripts/build-app.sh --install   # 另外複製到 /Applications
```

自檢（用假資料把面板真的開出來、送滑鼠事件、核對結果、各畫面存成 PNG；不碰真實資料）：

```bash
swift build && .build/debug/Jindu --selfcheck /tmp/jindu-check
```

開發時想用另一份資料：`JINDU_DATA_DIR=/某個資料夾 .build/debug/Jindu`

## 結構

- `Sources/JinduCore/`：不依賴介面的邏輯。`Models`（項目 → 分組 → 格子／清單項）、`Store`（所有修改的唯一入口，改完自動存檔）、`DayClock`（按「一天從幾點開始」歸日）、`GridMetrics`（格子排版與座標換算）。
- `Sources/Jindu/`：菜單欄 app。`AppDelegate`（菜單欄圖標）、`PanelController`（彈出／置頂／迷你條三種狀態與視窗位置）、`Views/`（介面）、`SelfCheck`（上面的自檢）。

## 還沒做

截止日與配速、循環任務、提醒方式設定、匯出匯入。
