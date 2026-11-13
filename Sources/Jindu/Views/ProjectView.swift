import JinduCore
import SwiftUI

/// 項目頁：總進度、近兩週節奏，下面是一個個分組。
struct ProjectView: View {
    let projectID: UUID
    @EnvironmentObject var store: Store
    @EnvironmentObject var panel: PanelController
    @State private var renaming = false
    @State private var draftName = ""
    @State private var confirmingDelete = false
    @State private var editingDeadline = false
    @State private var draggingGroup: UUID?
    @FocusState private var renameFocused: Bool

    var body: some View {
        if let project = store.project(projectID) {
            let now = Date()
            VStack(spacing: 0) {
                HeaderBar(onBack: { panel.route = .home }) {
                    if renaming {
                        TextField("項目名稱", text: $draftName)
                            .modifier(FieldStyle())
                            .focused($renameFocused)
                            .onSubmit(commitRename)
                            .onExitCommand { renaming = false }
                    } else {
                        Text(project.name)
                            .font(.system(size: 14, weight: .bold))
                            .lineLimit(1)
                            .allowsHitTesting(false)
                    }
                } trailing: {
                    MoreMenu {
                        Button("重新命名") {
                            draftName = project.name
                            renaming = true
                            renameFocused = true
                        }
                        Button(project.deadline == nil ? "設定截止日…" : "修改截止日…") { editingDeadline = true }
                        Button(project.archived ? "取消歸檔" : "歸檔") {
                            store.setArchived(project.id, !project.archived)
                            if !project.archived { panel.route = .home }
                        }
                        Divider()
                        Button("刪除項目…") { confirmingDelete = true }
                    }
                    WindowButtons()
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        if confirmingDelete { deleteBanner(project) }

                        if editingDeadline {
                            DeadlineEditor(current: project.deadline) { date in
                                store.setDeadline(date, project: project.id)
                                editingDeadline = false
                            } onCancel: {
                                editingDeadline = false
                            }
                            .padding(12)
                            .modifier(CardBackground())
                        }

                        // 只有循環任務的項目沒有「已完成／總數」可言，就不顯示統計卡
                        if project.total > 0 || project.deadline != nil {
                            ProjectStats(project: project, now: now)
                        }

                        ForEach(project.groups) { group in
                            GroupCard(projectID: project.id, group: group, now: now, dragging: $draggingGroup)
                                .onDrop(of: [.text], delegate: ReorderDropDelegate(target: group.id, dragging: $draggingGroup) { from, to in
                                    store.moveGroup(from, onto: to, project: project.id)
                                })
                        }

                        AddGroupForm(projectID: project.id, isFirst: project.groups.isEmpty)
                    }
                    .padding(12)
                }
            }
        } else {
            // 項目被刪掉了：回首頁
            Color.clear.onAppear { panel.route = .home }
        }
    }

    private func commitRename() {
        store.renameProject(projectID, to: draftName)
        renaming = false
    }

    private func deleteBanner(_ project: Project) -> some View {
        HStack(spacing: 8) {
            Text("刪除「\(project.name)」和裡面所有記錄？刪了找不回來。")
                .font(.system(size: 12))
                .foregroundStyle(Theme.danger)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            Button("取消") { confirmingDelete = false }
                .buttonStyle(PillButtonStyle(kind: .quiet))
            Button("刪除") {
                store.deleteProject(project.id)
                panel.route = .home
            }
            .buttonStyle(PillButtonStyle(kind: .danger))
        }
        .padding(10)
        .background(Theme.dangerSoft, in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ProjectStats: View {
    let project: Project
    let now: Date
    @EnvironmentObject var store: Store

    var body: some View {
        let clock = store.clock
        let dates = project.doneDates
        let today = clock.count(of: dates, onDayOf: now)

        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(project.isComplete ? "✓ \(project.doneCount)/\(project.total)" : "\(project.doneCount)/\(project.total)")
                    .font(.system(size: 20, weight: .bold))
                    .monospacedDigit()
                Text(percentText(project.fraction))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
                Spacer()
                Text("今日 +\(today)")
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(today > 0 ? Theme.accent : Theme.dim)
            }

            ProgressBar(fraction: project.fraction)

            if let deadline = project.deadline, let pace = project.pace(now: now, clock: clock) {
                PaceLine(pace: pace, deadline: deadline, now: now)
            }

            HStack(alignment: .bottom, spacing: 10) {
                Text("近 14 天")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.dim)
                DayBars(history: clock.history(of: dates, days: 14, now: now))
            }
            .padding(.top, 2)
        }
        .padding(12)
        .modifier(CardBackground())
    }
}

/// 新增分組：選形態（格子／清單／循環任務），填名字，格子再填起止編號。
private struct AddGroupForm: View {
    let projectID: UUID
    let isFirst: Bool
    @EnvironmentObject var store: Store
    @State private var kind: GroupKind = .grid
    @State private var name = ""
    @State private var start = ""
    @State private var end = ""
    @State private var problem: String?
    @FocusState private var focus: Field?

    private enum Field { case name, start, end }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(isFirst ? "加第一個分組" : "加分組")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                KindToggle(kind: $kind)
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                TextField(namePlaceholder, text: $name)
                    .modifier(FieldStyle())
                    .focused($focus, equals: .name)
                    .onSubmit(add)

                if kind == .grid {
                    TextField("起", text: $start)
                        .modifier(FieldStyle())
                        .frame(width: 52)
                        .focused($focus, equals: .start)
                        .onSubmit(add)
                        .onChange(of: start) { _, v in start = v.digitsOnly }
                    Text("–").foregroundStyle(Theme.dim)
                    TextField("止", text: $end)
                        .modifier(FieldStyle())
                        .frame(width: 52)
                        .focused($focus, equals: .end)
                        .onSubmit(add)
                        .onChange(of: end) { _, v in end = v.digitsOnly }
                }

                Button("添加", action: add)
                    .buttonStyle(PillButtonStyle())
            }

            if let problem {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.danger)
            }
        }
        .padding(12)
        .modifier(CardBackground())
    }

    private var namePlaceholder: String {
        switch kind {
        case .grid: return "名稱（如 第三章）"
        case .list: return "名稱（如 交稿清單）"
        case .routine: return "名稱（如 每日功課）"
        }
    }

    private func add() {
        problem = nil
        switch kind {
        case .grid:
            guard let s = Int(start) else { focus = .start; return }
            guard let e = Int(end) else { focus = .end; return }
            guard e >= s else {
                problem = "結束編號要大於或等於起始編號。"
                focus = .end
                return
            }
            guard store.addGridGroup(project: projectID, name: name, start: s, end: e) != nil else {
                problem = "一個分組最多 \(Store.maxGridCells) 格，拆成幾個分組吧。"
                return
            }
        case .list:
            store.addListGroup(project: projectID, name: name)
        case .routine:
            store.addRoutineGroup(project: projectID, name: name)
        }
        name = ""
        start = ""
        end = ""
        focus = .name
    }
}

private struct KindToggle: View {
    @Binding var kind: GroupKind

    var body: some View {
        HStack(spacing: 0) {
            segment("編號格子", .grid)
            segment("清單", .list)
            segment("循環任務", .routine)
        }
        .padding(2)
        .background(Theme.border.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
    }

    private func segment(_ title: String, _ value: GroupKind) -> some View {
        Button {
            kind = value
        } label: {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 3)
                .foregroundStyle(kind == value ? Theme.fg : Theme.dim)
                .background(kind == value ? Theme.surface : Color.clear, in: RoundedRectangle(cornerRadius: 5))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
