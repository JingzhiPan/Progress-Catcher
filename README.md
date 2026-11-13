# 進度表

Mac 菜單欄上的進度跟進小工具：一段編號逐格蓋章、一張清單逐項勾掉、或按頻率反覆出現的循環任務。可以設截止日看配速，可置頂浮在最上層，也可收成迷你條。

## 用法

- 點菜單欄圖標打開面板；右鍵圖標有「設定」和「退出」。
- 首頁是所有項目的進度，最近做過的排最前；今天輪到的循環任務匯總在最上面，可以直接勾。
- 點進項目後加分組：**編號格子**（填起止數字）、**清單**、或**循環任務**。
- 格子：點一下蓋章，再點取消；按住拖過去連續蓋。
- 循環任務的頻率：每天、每週固定幾天、每週／每月做夠 N 次、每隔 N 天。點一下記一次，做完了再點是撤銷。
- 截止日：項目或分組的「…」選單裡設。會顯示還剩多少、每天要做多少；比「從設定那天起每天做一樣多」慢就算落後，變紅。
- 提醒：設定裡三選一——系統通知（每天定時一條，沒事不發）、只在菜單欄圖標旁標小圓點、不提醒。
- 匯出／匯入：設定裡。匯入會取代現有全部資料，取代前自動備份。
- 圖釘：置頂。置頂後多一個按鈕可收成迷你條，只顯示正在做的那一組。
- 資料在 `~/Library/Application Support/Jindu/data.json`，每天自動備份到旁邊的 `backups/`。

## 開發

這台機器只有 Command Line Tools，沒有 Xcode，所以全程用 SwiftPM 加腳本。

```bash
./scripts/test.sh                  # 核心邏輯測試
./scripts/build-app.sh             # 打包成 build/進度表.app
./scripts/build-app.sh --install   # 另外複製到 /Applications
./scripts/make-icon.sh             # 由 Assets/icon.svg 重新產生 Assets/AppIcon.icns
```

圖標是一隻拱起來的毛毛蟲，由 `scripts/icon/inchworm.py` 畫出 SVG。那個腳本依賴 flat-creature 技能的生成器（不在倉庫裡）；要改造型或配色時設好 `FLAT_CREATURE_SCRIPTS` 再跑 `make-icon.sh`，平時直接用現成的 `Assets/icon.svg`。

自檢（用假資料把面板真的開出來、送滑鼠事件、核對結果、各畫面存成 PNG；不碰真實資料）：

```bash
swift build && .build/debug/Jindu --selfcheck /tmp/jindu-check
```

開發時想用另一份資料：`JINDU_DATA_DIR=/某個資料夾 .build/debug/Jindu`

## 結構

- `Sources/JinduCore/`：不依賴介面的邏輯。`Models`（項目 → 分組 → 格子／清單項／循環任務）、`Store`（所有修改的唯一入口，改完自動存檔）、`DayClock`（按「一天從幾點開始」歸日）、`Routine`（循環任務的頻率規則與狀態）、`Pace`（截止日配速，以及「今天有幾件事要提醒」）、`GridMetrics`（格子排版與座標換算）。
- `Sources/Jindu/`：菜單欄 app。`AppDelegate`（菜單欄圖標與小圓點、每分鐘的計時）、`PanelController`（彈出／置頂／迷你條三種狀態與視窗位置）、`Reminders`（系統通知）、`Views/`（介面）、`SelfCheck`（上面的自檢）。

## 還沒做

全域快捷鍵、開機自啟。
