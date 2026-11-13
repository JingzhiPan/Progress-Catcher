import AppKit
import JinduCore

/// 開發用自檢：`Jindu --selfcheck <輸出資料夾>`
/// 用假資料（只在記憶體裡）把面板真的開出來，往格子上送滑鼠事件，核對結果，再把各個畫面存成 PNG。
/// 不碰真實的資料檔。
@MainActor
final class SelfCheck {
    private let store: Store
    private let panel: PanelController
    private let statusItem: NSStatusItem
    private let outDir: URL
    private var failures = 0

    init(store: Store, panel: PanelController, statusItem: NSStatusItem, outDir: URL) {
        self.store = store
        self.panel = panel
        self.statusItem = statusItem
        self.outDir = outDir
    }

    func start() {
        DebugProbe.enabled = true
        Task { @MainActor in
            await run()
            print(failures == 0 ? "SELFCHECK PASS" : "SELFCHECK FAIL (\(failures))")
            exit(failures == 0 ? 0 : 1)
        }
    }

    private func run() async {
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        let now = Date()
        let day: TimeInterval = 86400

        // --- 假資料 ---
        let book = store.addProject(name: "示例譯稿", now: now.addingTimeInterval(-20 * day))
        let ch3 = store.addGridGroup(project: book, name: "第三章", start: 77, end: 124)!
        let ch4 = store.addGridGroup(project: book, name: "第四章", start: 125, end: 160)!
        let todo = store.addListGroup(project: book, name: "交稿前")!
        for (offset, n) in (77...95).enumerated() {
            store.setStamp(n, done: true, group: ch3, project: book, now: now.addingTimeInterval(-Double(13 - offset % 13) * day))
        }
        let first = store.addItem("核對引文頁碼", group: todo, project: book)!
        store.addItem("統一「儀式」譯名", group: todo, project: book)
        store.addItem("寄給編輯", group: todo, project: book)
        store.setItemDone(first, done: true, group: todo, project: book, now: now.addingTimeInterval(-2 * day))

        let thesis = store.addProject(name: "論文第二章", now: now.addingTimeInterval(-9 * day))
        let sections = store.addGridGroup(project: thesis, name: "小節", start: 1, end: 12)!
        for n in 1...5 { store.setStamp(n, done: true, group: sections, project: thesis, now: now.addingTimeInterval(-3 * day)) }
        store.setStamp(96, done: true, group: ch3, project: book, now: now.addingTimeInterval(-60))

        // --- 菜單欄 ---
        await pause(0.3)
        let title = statusItem.button?.title ?? ""
        check(title.trimmingCharacters(in: .whitespaces) == "21/87", "菜單欄顯示當前項目進度（實際：\(title)）")
        let buttonFrame = statusItem.button?.window?.frame ?? .zero
        check(buttonFrame.width > 0, "菜單欄圖標已放上去（位置 \(Int(buttonFrame.minX)),\(Int(buttonFrame.minY))）")

        // --- 未置頂：出現在圖標下面 ---
        statusItem.button?.performClick(nil)
        await pause(0.5)
        check(panel.isVisible, "點圖標後面板出現")
        let frame = panel.window.frame
        if buttonFrame.width > 0 {
            check(frame.maxY <= buttonFrame.minY + 1, "面板在菜單欄圖標下方")
        }
        snapshot("1-首頁")

        // 之後的步驟先置頂再做：未置頂的面板「點別處就收起」，自檢時使用者真的在別處點一下就會把它關掉。
        panel.setPinned(true)
        // 收起再打開：置頂狀態下重新出現的面板不會搶鍵盤焦點，正好用來驗「不是焦點時第一下點擊也生效」。
        panel.hide()
        panel.show()
        await pause(0.3)

        // --- 項目頁 ---
        panel.route = .project(book)
        await pause(0.6)
        snapshot("2-項目頁")

        // --- 點一格 ---
        guard let grid = DebugProbe.gridFrames[ch3] else {
            check(false, "找得到第三章格子的位置")
            return
        }
        let metrics = GridMetrics(width: grid.width, count: 48)
        func windowPoint(_ index: Int) -> NSPoint {
            let c = metrics.center(of: index)
            let height = panel.window.contentView?.bounds.height ?? 0
            return NSPoint(x: grid.minX + c.x, y: height - (grid.minY + c.y))
        }
        // 97 是第 20 格（序號 20）
        mouse(.leftMouseDown, windowPoint(20))
        await pause(0.08)
        mouse(.leftMouseUp, windowPoint(20))
        await pause(0.3)
        check(store.project(book)?.groups[0].isDone(97) == true,
              "點一下第 97 格 → 蓋上（當時面板\(panel.window.isKeyWindow ? "是" : "不是")鍵盤焦點）")

        mouse(.leftMouseDown, windowPoint(20))
        await pause(0.08)
        mouse(.leftMouseUp, windowPoint(20))
        await pause(0.3)
        check(store.project(book)?.groups[0].isDone(97) == false, "再點一下第 97 格 → 取消")

        // --- 拖過一排：在同一排裡連蓋五格（排數和欄數隨面板寬度而定，所以現算） ---
        let rowStart = (metrics.row(of: 20) + 1) * metrics.cols
        let dragged = Array(rowStart..<(rowStart + 5))
        mouse(.leftMouseDown, windowPoint(dragged[0]))
        await pause(0.05)
        for i in dragged.dropFirst() {
            mouse(.leftMouseDragged, windowPoint(i))
            await pause(0.05)
        }
        mouse(.leftMouseUp, windowPoint(dragged[4]))
        await pause(0.3)
        let expected = dragged.map { 77 + $0 }
        let stampedNow = (store.project(book)?.groups[0].stamps.keys.filter { $0 > 96 } ?? []).sorted()
        check(stampedNow == expected, "按住拖過 \(expected.first!)–\(expected.last!) → 剛好這五格蓋上（實際：\(stampedNow)，\(metrics.cols) 欄）")
        check(statusItem.button?.title.trimmingCharacters(in: .whitespaces) == "26/87", "菜單欄數字跟著變成 26/87（實際：\(statusItem.button?.title ?? "")）")
        snapshot("3-蓋章後")

        // --- 置頂 + 迷你條 ---
        check(panel.pinned && panel.window.level == .floating, "置頂後浮在最上層")
        snapshot("4-置頂")
        let fullFrame = panel.window.frame
        panel.setMini(true)
        await pause(0.6)
        let miniFrame = panel.window.frame
        check(panel.mini && miniFrame.height < fullFrame.height, "迷你條比完整面板小")
        check(abs(miniFrame.maxX - fullFrame.maxX) < 1 && abs(miniFrame.maxY - fullFrame.maxY) < 1, "迷你條和完整面板共用右上角")
        snapshot("5-迷你條")

        store.setCurrentGroup(todo, project: book)
        await pause(0.4)
        snapshot("6-迷你條-清單")
        store.setCurrentGroup(ch4, project: book)
        await pause(0.2)

        panel.setMini(false)
        await pause(0.4)
        check(panel.window.frame.size == fullFrame.size, "展開後回到原來的大小")

        // --- 設定頁 ---
        panel.route = .settings
        await pause(0.4)
        snapshot("7-設定")

        // --- 深色 ---
        NSApp.appearance = NSAppearance(named: .darkAqua)
        panel.route = .project(book)
        await pause(0.6)
        snapshot("8-項目頁-深色")
        panel.route = .home
        await pause(0.4)
        snapshot("9-首頁-深色")
        NSApp.appearance = nil

        // --- 取消置頂後按 Esc 收起 ---
        panel.setPinned(false)
        check(panel.isVisible && !panel.pinned, "取消置頂後面板留在原地")
        panel.window.cancelOperation(nil)
        await pause(0.2)
        check(!panel.isVisible, "未置頂時按 Esc 收起面板")
    }

    // MARK: 工具

    private func check(_ ok: Bool, _ what: String) {
        print("\(ok ? "✓" : "✗") \(what)")
        if !ok { failures += 1 }
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func mouse(_ type: NSEvent.EventType, _ point: NSPoint) {
        guard let event = NSEvent.mouseEvent(
            with: type, location: point, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: panel.window.windowNumber, context: nil,
            eventNumber: 0, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1
        ) else { return }
        NSApp.postEvent(event, atStart: false)
    }

    private func snapshot(_ name: String) {
        guard let view = panel.window.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            check(false, "截圖 \(name)")
            return
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        let url = outDir.appendingPathComponent("\(name).png")
        do {
            try rep.representation(using: .png, properties: [:])?.write(to: url)
        } catch {
            check(false, "截圖 \(name)：\(error.localizedDescription)")
        }
    }
}
