import AppKit
import Combine
import JinduCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var store: Store!
    private var panel: PanelController!
    private var statusItem: NSStatusItem!
    private var bag = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        let selfCheckDir = Self.argument(after: "--selfcheck").map { URL(fileURLWithPath: $0) }

        // 自檢時資料只放記憶體，不碰真實的資料檔。
        store = Store(directory: selfCheckDir == nil ? Self.dataDirectory() : nil)
        panel = PanelController(store: store)
        setUpStatusItem()

        store.$data
            .sink { [weak self] data in self?.refreshStatus(data) }
            .store(in: &bag)

        if let selfCheckDir {
            SelfCheck(store: store, panel: panel, statusItem: statusItem, outDir: selfCheckDir).start()
        } else {
            panel.restore()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flush()
    }

    // MARK: 菜單欄

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        let image = NSImage(systemSymbolName: "checkmark.square", accessibilityDescription: "進度表")
        image?.isTemplate = true
        button.image = image
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        button.target = self
        button.action = #selector(statusClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        panel.statusButton = button
    }

    private func refreshStatus(_ data: AppData) {
        guard let button = statusItem.button else { return }
        if let project = data.focusProject, project.total > 0 {
            button.title = " \(project.doneCount)/\(project.total)"
            button.toolTip = "進度表 · \(project.name)"
        } else {
            button.title = ""
            button.toolTip = "進度表"
        }
    }

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
