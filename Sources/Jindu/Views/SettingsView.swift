import AppKit
import JinduCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var panel: PanelController

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

                    if let url = store.fileURL {
                        section("資料", hint: "所有記錄都在這一個檔案裡，每天自動留一份備份（backups 資料夾，保留最近 10 份）。") {
                            Button("在 Finder 中顯示資料檔") {
                                store.flush()
                                NSWorkspace.shared.activateFileViewerSelecting([url])
                            }
                            .buttonStyle(PillButtonStyle(kind: .quiet))
                        }
                    }

                    Button("退出進度表") { NSApp.terminate(nil) }
                        .buttonStyle(PillButtonStyle(kind: .danger))
                        .padding(.top, 4)
                }
                .padding(12)
            }
        }
    }

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
