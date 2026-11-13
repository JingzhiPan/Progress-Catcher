import AppKit
import JinduCore
import UserNotifications

/// 系統通知：每天到了設定的時間，如果還有該做沒做的事，發一條。
/// 內容要看當下的狀態，所以不預先排程，而是由 app 每分鐘檢查一次、到點現發。
@MainActor
final class Reminders: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    enum Permission {
        /// 沒有打包成 .app（開發時直接跑執行檔），系統通知用不了
        case unavailable
        case notAsked
        case granted
        case denied
    }

    @Published private(set) var permission: Permission
    /// 點了通知之後要做什麼（打開面板）
    var onOpen: (() -> Void)?

    private let store: Store
    private let defaults = UserDefaults.standard
    private static let lastDayKey = "lastNotifiedDay"

    init(store: Store) {
        self.store = store
        permission = Bundle.main.bundleIdentifier == nil ? .unavailable : .notAsked
        super.init()
        center?.delegate = self
        refreshPermission()
    }

    private var center: UNUserNotificationCenter? {
        Bundle.main.bundleIdentifier == nil ? nil : UNUserNotificationCenter.current()
    }

    func refreshPermission() {
        center?.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            Task { @MainActor in
                switch status {
                case .authorized, .provisional: self.permission = .granted
                case .denied: self.permission = .denied
                default: self.permission = .notAsked
                }
            }
        }
    }

    /// 向系統要通知權限（第一次會跳出系統的詢問框）。
    func requestPermission() {
        center?.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            Task { @MainActor in self.permission = granted ? .granted : .denied }
        }
    }

    /// 每分鐘呼叫一次。到點、今天還沒發過、確實有事 → 發。
    func tick(now: Date = Date()) {
        let settings = store.data.settings
        guard settings.reminder == .notification, permission == .granted else { return }
        let cal = Calendar.current
        guard let fireTime = cal.date(bySettingHour: settings.notifyHour, minute: settings.notifyMinute, second: 0, of: now),
              now >= fireTime else { return }
        let c = cal.dateComponents([.year, .month, .day], from: now)
        let dayKey = "\(c.year ?? 0)-\(c.month ?? 0)-\(c.day ?? 0)"
        guard defaults.string(forKey: Self.lastDayKey) != dayKey else { return }
        defaults.set(dayKey, forKey: Self.lastDayKey)

        guard let body = Self.summary(of: store.data, now: now) else { return }
        post(title: "進度表", body: body)
    }

    func sendTest() {
        let body = Self.summary(of: store.data, now: Date()) ?? "這是一條測試通知。今天沒有待處理的事。"
        post(title: "進度表", body: body)
    }

    /// 通知的內容；沒有需要提醒的事就回傳 nil。
    static func summary(of data: AppData, now: Date) -> String? {
        let clock = DayClock(startHour: data.settings.dayStartHour)
        var lines: [String] = []

        let pending = data.todayRoutines(now: now, clock: clock).filter(\.state.needsAttention)
        if !pending.isEmpty {
            let names = pending.prefix(4).map { item -> String in
                if case .quota(_, let per) = item.routine.rule {
                    return "\(item.routine.title)（\(per == .week ? "本週" : "本月") \(item.state.done)/\(item.state.target)）"
                }
                return item.routine.title
            }
            let more = pending.count > 4 ? " 等 \(pending.count) 件" : ""
            lines.append("今天還沒做：" + names.joined(separator: "、") + more)
        }

        for info in data.openDeadlines(now: now, clock: clock).filter(\.pace.needsAttention).prefix(3) {
            lines.append("\(info.title)：" + paceText(info.pace, deadline: info.deadline, now: now, detailed: false))
        }

        return lines.isEmpty ? nil : lines.joined(separator: "\n")
    }

    private func post(title: String, body: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        center.add(UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)) { error in
            if let error { NSLog("進度表：通知沒發出去 \(error.localizedDescription)") }
        }
    }

    // MARK: UNUserNotificationCenterDelegate

    // 菜單欄 app 沒有「前景／背景」之分，照常顯示橫幅。
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        await MainActor.run { self.onOpen?() }
    }
}
