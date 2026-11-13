import AppKit
import Combine
import JinduCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: Store!
    private var panel: PanelController!
    private var statusItem: NSStatusItem!
    private var reminders: Reminders!
    private var minuteTimer: Timer?
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let selfCheckDir = Self.argument(after: "--selfcheck").map { URL(fileURLWithPath: $0) }

        // 自檢時資料放在輸出資料夾底下的臨時位置，不碰真實的資料檔。
        if let selfCheckDir {
            let scratch = selfCheckDir.appendingPathComponent("data")
            try? FileManager.default.removeItem(at: scratch)
            store = Store(directory: scratch)
        } else {
            store = Store(directory: Self.dataDirectory())
        }
        // agent（MCP 服務）改了資料檔，這邊馬上重讀，面板和菜單欄跟著變
        store.startWatching()
        reminders = Reminders(store: store)
        panel = PanelController(store: store, reminders: reminders)
        reminders.onOpen = { [weak self] in
            guard let self else { return }
            if !self.panel.isVisible { self.panel.show() }
        }
        setUpStatusItem()

        store.$data
            .sink { [weak self] data in self?.refreshStatus(data) }
            .store(in: &bag)

        if let selfCheckDir {
            SelfCheck(store: store, panel: panel, statusItem: statusItem, outDir: selfCheckDir).start()
        } else {
            panel.restore()
            startMinuteTimer()
        }
    }

    /// 每分鐘一次：過了午夜（或日界線）讓菜單欄標記和面板重算，並檢查是不是到了發通知的時間。
    private func startMinuteTimer() {
        let timer = Timer(timeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.store.refresh() // 保險：萬一檔案監聽漏了一次
                self.refreshStatus(self.store.data)
                self.panel.refreshClock()
                self.reminders.tick()
            }
        }
        timer.tolerance = 10
        RunLoop.main.add(timer, forMode: .common)
        minuteTimer = timer
        reminders.tick()
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flush()
    }

    // MARK: 菜單欄

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.image = MenuBarGlyph.image()
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        button.target = self
        button.action = #selector(statusClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        panel.statusButton = button
    }

    private func refreshStatus(_ data: AppData) {
        guard let button = statusItem.button else { return }
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let title = NSMutableAttributedString()
        var tips = ["進度表"]

        if let project = data.focusProject {
            tips.append(project.name)
            if project.total > 0 {
                title.append(NSAttributedString(string: " \(project.doneCount)/\(project.total)", attributes: [.font: font]))
            }
        }

        // 小圓點：今天該做沒做的循環任務，或配速落後／過期的截止日
        if data.settings.reminder != .off {
            let clock = DayClock(startHour: data.settings.dayStartHour)
            let attention = data.attentionCount(now: Date(), clock: clock)
            if attention > 0 {
                title.append(NSAttributedString(string: " ●", attributes: [
                    .font: NSFont.systemFont(ofSize: 8),
                    .foregroundColor: NSColor(hex: 0xe0796c),
                    .baselineOffset: 1.5,
                ]))
                tips.append("\(attention) 件事待處理")
            }
            attentionCount = attention
        } else {
            attentionCount = 0
        }

        button.attributedTitle = title
        button.toolTip = tips.joined(separator: " · ")
    }

    /// 目前菜單欄標記代表幾件事（自檢時讀）。
    private(set) var attentionCount = 0

    @objc private func statusClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            panel.toggle()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: panel.isVisible ? "收起面板" : "打開面板", action: #selector(togglePanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "設定…", action: #selector(openSettings), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出進度表", action: #selector(quit), keyEquivalent: "q").target = self
        // 臨時掛上選單再觸發一次點擊，是讓左鍵和右鍵行為分開的慣用寫法。
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func togglePanel() { panel.toggle() }

    @objc private func openSettings() {
        if panel.mini { panel.setMini(false) }
        panel.route = .settings
        if !panel.isVisible { panel.show() }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    // MARK: 輔助

    private static func argument(after flag: String) -> String? {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: flag), args.indices.contains(i + 1) else { return nil }
        return args[i + 1]
    }

    /// 預設在 ~/Library/Application Support/Jindu；可用環境變數 JINDU_DATA_DIR 改到別處（開發時用）。
    private static func dataDirectory() -> URL {
        if let custom = ProcessInfo.processInfo.environment["JINDU_DATA_DIR"], !custom.isEmpty {
            return URL(fileURLWithPath: custom)
        }
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Jindu")
    }
}
