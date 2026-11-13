import AppKit
import JinduCore

/// 開發用自檢：`Jindu --selfcheck <輸出資料夾>`
/// 用假資料（存在輸出資料夾的 data/ 底下）把面板真的開出來，往格子上送滑鼠事件，核對結果，再把各個畫面存成 PNG。
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
        let book = store.addProject(name: "示例書稿", now: now.addingTimeInterval(-20 * day))
        let ch3 = store.addGridGroup(project: book, name: "第三章", start: 77, end: 124)!
        let ch4 = store.addGridGroup(project: book, name: "第四章", start: 125, end: 160)!
        let todo = store.addListGroup(project: book, name: "交稿前")!
        for (offset, n) in (77...95).enumerated() {
            store.setStamp(n, done: true, group: ch3, project: book, now: now.addingTimeInterval(-Double(13 - offset % 13) * day))
        }
        let first = store.addItem("核對頁碼", group: todo, project: book)!
        store.addItem("統一術語", group: todo, project: book)
        store.addItem("寄給編輯", group: todo, project: book)
        store.setItemDone(first, done: true, group: todo, project: book, now: now.addingTimeInterval(-2 * day))
        // 截止日：整個項目 6 天後（5 天前設的，進度落後）；第四章 3 天後
        store.setDeadline(now.addingTimeInterval(6 * day), project: book, now: now.addingTimeInterval(-5 * day))
        store.setDeadline(now.addingTimeInterval(3 * day), group: ch4, project: book, now: now)

        let course = store.addProject(name: "課程作業", now: now.addingTimeInterval(-9 * day))
        let sections = store.addGridGroup(project: course, name: "小節", start: 1, end: 12)!
        for n in 1...5 { store.setStamp(n, done: true, group: sections, project: course, now: now.addingTimeInterval(-3 * day)) }

        // 循環任務
        let habits = store.addProject(name: "日常", now: now.addingTimeInterval(-12 * day))
        let daily = store.addRoutineGroup(project: habits, name: "每日功課")!
        let words = store.addRoutine("背單字", rule: .daily, group: daily, project: habits, now: now.addingTimeInterval(-10 * day))!
        for back in [9, 8, 6, 5, 4, 2, 1] {
            store.tapRoutine(words, group: daily, project: habits, now: now.addingTimeInterval(-Double(back) * day))
        }
        let notes = store.addRoutine("寫筆記", rule: .quota(times: 3, per: .week), group: daily, project: habits, now: now.addingTimeInterval(-10 * day))!
        store.tapRoutine(notes, group: daily, project: habits, now: now)
        let todayWeekday = Calendar.current.component(.weekday, from: now)
        store.addRoutine("運動", rule: .weekdays([todayWeekday % 7 + 1, (todayWeekday + 2) % 7 + 1]), group: daily, project: habits, now: now.addingTimeInterval(-10 * day))
        store.addRoutine("整理書桌", rule: .everyN(days: 3), group: daily, project: habits, now: now.addingTimeInterval(-9 * day))

        store.setStamp(96, done: true, group: ch3, project: book, now: now.addingTimeInterval(-60))

        // --- 菜單欄 ---
        await pause(0.3)
        let title = statusItem.button?.title ?? ""
        check(title.contains("21/87"), "菜單欄顯示當前項目進度（實際：\(title)）")
        // 待處理：背單字、寫筆記(1/3)、整理書桌（起始日 +9 天，今天輪到）、項目截止日落後
        check(title.contains("●"), "有事待處理時菜單欄出現小圓點")
        let delegate = NSApp.delegate as? AppDelegate
        check(delegate?.attentionCount == 4, "待處理共 4 件（實際：\(delegate?.attentionCount ?? -1)）")
        // 菜單欄圖標本身存一張圖出來看
        try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
        if let glyph = statusItem.button?.image, let tiff = glyph.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff) {
            check(glyph.isTemplate && glyph.size.height == 15, "菜單欄圖標是模板圖，高 15pt（實際 \(glyph.size)）")
            try? rep.representation(using: .png, properties: [:])?.write(to: outDir.appendingPathComponent("0-菜單欄圖標.png"))
        } else {
            check(false, "菜單欄圖標畫得出來")
        }
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
        check(statusItem.button?.title.contains("26/87") == true, "菜單欄數字跟著變成 26/87（實際：\(statusItem.button?.title ?? "")）")
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

        // --- 首頁「今天」：點一下循環任務 ---
        panel.route = .home
        await pause(0.5)
        func routineLog(_ id: UUID) -> Int {
            store.project(habits)?.groups[0].routines.first { $0.id == id }?.log.count ?? -1
        }
        if let box = DebugProbe.frames["today-背單字"] {
            let height = panel.window.contentView?.bounds.height ?? 0
            let point = NSPoint(x: box.midX, y: height - box.midY)
            let before = routineLog(words)
            mouse(.leftMouseDown, point)
            await pause(0.08)
            mouse(.leftMouseUp, point)
            await pause(0.3)
            check(routineLog(words) == before + 1, "在首頁「今天」點背單字 → 記一次")
            check(delegate?.attentionCount == 3, "待處理減為 3 件（實際：\(delegate?.attentionCount ?? -1)）")
        } else {
            check(false, "首頁「今天」裡找得到背單字")
        }
        snapshot("7-首頁-今天")

        panel.route = .project(habits)
        await pause(0.5)
        snapshot("7-循環任務")

        // --- 匯出再匯入 ---
        if let exported = try? store.exportData() {
            let before = store.data
            store.deleteProject(course)
            let restored = (try? store.importData(exported)) != nil
            check(restored && store.data.projects.count == before.projects.count, "匯出後刪掉一個項目，再匯入 → 項目都回來了")
        } else {
            check(false, "匯出資料")
        }

        // --- 設定頁 ---
        panel.route = .settings
        await pause(0.4)
        snapshot("7-設定")
        store.setReminder(.off)
        await pause(0.2)
        check(statusItem.button?.title.contains("●") == false, "提醒設成「不提醒」後小圓點消失")
        store.setReminder(.notification)
        await pause(0.3)
        snapshot("7-設定-系統通知")
        store.setReminder(.badge)

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
