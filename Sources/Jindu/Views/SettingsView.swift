import AppKit
import JinduCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var panel: PanelController
    @EnvironmentObject var reminders: Reminders
    @State private var pendingImport: PendingImport?
    @State private var dataMessage: String?

    private struct PendingImport {
        let name: String
        let data: Data
    }

    var body: some View {
        VStack(spacing: 0) {
            HeaderBar(onBack: { panel.route = .home }) {
                Text("設定")
                    .font(.system(size: 14, weight: .bold))
                    .allowsHitTesting(false)
            } trailing: {
                WindowButtons()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    section("菜單欄顯示哪個項目", hint: "圖標旁邊的數字是這個項目的「已完成／總數」。") {
                        Picker("", selection: Binding(
                            get: { store.data.settings.menuBarProjectID },
                            set: { store.setMenuBarProject($0) }
                        )) {
                            Text("最近操作的項目").tag(UUID?.none)
                            ForEach(store.data.activeProjects) { project in
                                Text(project.name).tag(UUID?.some(project.id))
                            }
                        }
                        .labelsHidden()
                    }

                    reminderSection

                    section("一天從幾點開始", hint: "過了這個時間才算新的一天。常熬夜過零點，可以設成 04:00，凌晨做的就還算前一天。") {
                        Picker("", selection: Binding(
                            get: { store.data.settings.dayStartHour },
                            set: { store.setDayStartHour($0) }
                        )) {
                            ForEach(0..<7, id: \.self) { hour in
                                Text(String(format: "%02d:00", hour)).tag(hour)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 100)
                    }

                    dataSection

                    Button("退出進度表") { NSApp.terminate(nil) }
                        .buttonStyle(PillButtonStyle(kind: .danger))
                        .padding(.top, 4)
                }
                .padding(12)
            }
        }
        .onAppear { reminders.refreshPermission() }
    }

    // MARK: 提醒

    private var reminderSection: some View {
        let mode = store.data.settings.reminder
        return section("提醒方式", hint: reminderHint(mode)) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 0) {
                    reminderOption("系統通知", .notification)
                    reminderOption("只標記菜單欄", .badge)
                    reminderOption("不提醒", .off)
                }
                .padding(2)
                .background(Theme.border.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
                .fixedSize()

                if mode == .notification {
                    HStack(spacing: 8) {
                        Text("每天").font(.system(size: 12))
                        DatePicker("", selection: Binding(
                            get: {
                                Calendar.current.date(bySettingHour: store.data.settings.notifyHour,
                                                      minute: store.data.settings.notifyMinute, second: 0, of: Date()) ?? Date()
                            },
                            set: { date in
                                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                                store.setNotifyTime(hour: c.hour ?? 21, minute: c.minute ?? 0)
                            }
                        ), displayedComponents: .hourAndMinute)
                        .datePickerStyle(.stepperField)
                        .labelsHidden()
                        .fixedSize()
                        Text("提醒一次").font(.system(size: 12))
                        Spacer(minLength: 0)
                    }

                    switch reminders.permission {
                    case .granted:
                        Button("發一條測試通知") { reminders.sendTest() }
                            .buttonStyle(PillButtonStyle(kind: .quiet))
                    case .notAsked:
                        Button("允許進度表發通知…") { reminders.requestPermission() }
                            .buttonStyle(PillButtonStyle())
                    case .denied:
                        Text("系統沒有允許「進度表」發通知。到「系統設定 › 通知 › 進度表」打開後再回來。")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.danger)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("打開系統的通知設定") {
                            if let url = URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") {
                                NSWorkspace.shared.open(url)
                            }
                        }
                        .buttonStyle(PillButtonStyle(kind: .quiet))
                    case .unavailable:
                        Text("現在是直接跑執行檔（開發模式），系統通知要打包成 .app 才能用。")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.dim)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func reminderOption(_ title: String, _ value: ReminderMode) -> some View {
        let selected = store.data.settings.reminder == value
        return Button {
            store.setReminder(value)
            if value == .notification && reminders.permission == .notAsked { reminders.requestPermission() }
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .foregroundStyle(selected ? Theme.fg : Theme.dim)
                .background(selected ? Theme.surface : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func reminderHint(_ mode: ReminderMode) -> String {
        switch mode {
        case .notification:
            return "今天輪到的循環任務還沒做、或截止日的配速落後時：菜單欄圖標旁出現小圓點，並在上面的時間發一條系統通知。沒事就不發。"
        case .badge:
            return "今天輪到的循環任務還沒做、或截止日的配速落後時：菜單欄圖標旁出現小圓點。不彈通知。"
        case .off:
            return "什麼都不提醒，打開面板才看得到。"
        }
    }

    // MARK: 資料

    @ViewBuilder
    private var dataSection: some View {
        if let url = store.fileURL {
            section("資料", hint: "所有記錄都在一個檔案裡，每天自動留一份備份（backups 資料夾，保留最近 10 份）。匯入會取代現有的全部資料，取代前也會先備份。") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Button("匯出…", action: exportFile).buttonStyle(PillButtonStyle(kind: .quiet))
                        Button("匯入…", action: pickImportFile).buttonStyle(PillButtonStyle(kind: .quiet))
                        Button("在 Finder 中顯示") {
                            store.flush()
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        .buttonStyle(PillButtonStyle(kind: .quiet))
                    }

                    if let pendingImport {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("用「\(pendingImport.name)」取代現有的全部資料？")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.danger)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 6) {
                                Spacer()
                                Button("取消") { self.pendingImport = nil }
                                    .buttonStyle(PillButtonStyle(kind: .quiet))
                                Button("取代") { confirmImport(pendingImport) }
                                    .buttonStyle(PillButtonStyle(kind: .danger))
                            }
                        }
                        .padding(10)
                        .background(Theme.dangerSoft, in: RoundedRectangle(cornerRadius: 8))
                    }

                    if let dataMessage {
                        Text(dataMessage)
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.accent)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }

    private func exportFile() {
        dataMessage = nil
        guard let raw = try? store.exportData() else {
            dataMessage = "匯出失敗。"
            return
        }
        let c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = String(format: "進度表-%04d-%02d-%02d.json", c.year ?? 0, c.month ?? 0, c.day ?? 0)
        savePanel.allowedContentTypes = [.json]
        savePanel.level = .modalPanel // 比置頂的面板還高，不會被擋住
        let url: URL? = panel.runModal { savePanel.runModal() == .OK ? savePanel.url : nil }
        guard let url else { return }
        do {
            try raw.write(to: url, options: .atomic)
            dataMessage = "已匯出到 \(url.lastPathComponent)。"
        } catch {
            dataMessage = "寫不進去：\(error.localizedDescription)"
        }
    }

    private func pickImportFile() {
        dataMessage = nil
        let openPanel = NSOpenPanel()
        openPanel.allowedContentTypes = [.json]
        openPanel.allowsMultipleSelection = false
        openPanel.level = .modalPanel
        let url: URL? = panel.runModal { openPanel.runModal() == .OK ? openPanel.url : nil }
        guard let url else { return }
        guard let raw = try? Data(contentsOf: url) else {
            dataMessage = "讀不了這個檔案。"
            return
        }
        pendingImport = PendingImport(name: url.lastPathComponent, data: raw)
    }

    private func confirmImport(_ pending: PendingImport) {
        do {
            try store.importData(pending.data)
            dataMessage = "已匯入 \(pending.name)，共 \(store.data.projects.count) 個項目。"
        } catch {
            dataMessage = "「\(pending.name)」不是進度表匯出的檔案，沒有動現有資料。"
        }
        pendingImport = nil
    }

    // MARK: 共用

    private func section<Content: View>(_ title: String, hint: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 12, weight: .bold))
            content()
            Text(hint)
                .font(.system(size: 11))
                .foregroundStyle(Theme.dim)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .modifier(CardBackground())
    }
}
