import JinduCore
import SwiftUI

/// 首頁：所有項目的進度一覽，最近做過的排最前。
struct HomeView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var panel: PanelController
    @State private var newName = ""
    @State private var showArchived = false
    @FocusState private var addFocused: Bool

    var body: some View {
        let now = Date()
        let clock = store.clock
        let active = store.data.activeProjects
        let archived = store.data.archivedProjects
        let todayTotal = active.reduce(0) { $0 + clock.count(of: $1.doneDates, onDayOf: now) }
        let todayRoutines = store.data.todayRoutines(now: now, clock: clock)

        VStack(spacing: 0) {
            HeaderBar {
                HStack(spacing: 8) {
                    Text("進度表").font(.system(size: 14, weight: .bold))
                    if todayTotal > 0 {
                        Text("今日 +\(todayTotal)")
                            .font(.system(size: 11, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(Theme.accent)
                    }
                }
                .allowsHitTesting(false)
            } trailing: {
                IconButton(symbol: "gearshape", help: "設定") { panel.route = .settings }
                WindowButtons()
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if !todayRoutines.isEmpty {
                        TodaySection(items: todayRoutines)
                    }

                    if active.isEmpty {
                        Text("還沒有項目。\n在下面輸入名字，點「添加」開始記錄。")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.dim)
                            .multilineTextAlignment(.center)
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 28)
                    }

                    ForEach(active) { project in
                        ProjectCard(project: project, now: now, clock: clock)
                    }

                    addRow

                    if !archived.isEmpty {
                        archivedSection(archived)
                    }
                }
                .padding(12)
            }
        }
    }

    private var addRow: some View {
        HStack(spacing: 8) {
            TextField("新項目名稱", text: $newName)
                .modifier(FieldStyle())
                .focused($addFocused)
                .onSubmit(add)
            Button("添加", action: add)
                .buttonStyle(PillButtonStyle())
        }
        .padding(.top, 2)
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            addFocused = true
            return
        }
        let id = store.addProject(name: name)
        newName = ""
        panel.route = .project(id)
    }

    private func archivedSection(_ archived: [Project]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                showArchived.toggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: showArchived ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                    Text("已歸檔（\(archived.count)）")
                        .font(.system(size: 11))
                }
                .foregroundStyle(Theme.dim)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showArchived {
                ForEach(archived) { project in
                    HStack(spacing: 8) {
                        Text(project.name).font(.system(size: 12)).lineLimit(1)
                        Text("\(project.doneCount)/\(project.total)")
                            .font(.system(size: 11)).monospacedDigit()
                            .foregroundStyle(Theme.dim)
                        Spacer()
                        Button("打開") { panel.route = .project(project.id) }
                            .buttonStyle(PillButtonStyle(kind: .quiet))
                        Button("取消歸檔") { store.setArchived(project.id, false) }
                            .buttonStyle(PillButtonStyle(kind: .quiet))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .modifier(CardBackground())
                }
            }
        }
        .padding(.top, 6)
    }
}

private struct ProjectCard: View {
    let project: Project
    let now: Date
    let clock: DayClock
    @EnvironmentObject var store: Store
    @EnvironmentObject var panel: PanelController
    @State private var hover = false

    var body: some View {
        let today = clock.count(of: project.doneDates, onDayOf: now)
        let routines = project.groups.filter { $0.kind == .routine }.flatMap(\.routines)
            .map { $0.state(now: now, clock: clock) }.filter(\.isDueToday)
        let routinesDone = routines.filter(\.isSatisfied).count
        // 只有循環任務的項目沒有總數，卡片改顯示今天做了幾件
        let routineOnly = project.total == 0 && !routines.isEmpty
        // 卡片上只放一條截止日：有落後／過期的先顯示它，否則顯示最近的那個
        let deadlines = project.openDeadlines(now: now, clock: clock)
        let nearest = deadlines.first(where: \.pace.needsAttention) ?? deadlines.first

        Button {
            panel.route = .project(project.id)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(project.name)
                        .font(.system(size: 13, weight: .bold))
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Text(routineOnly
                         ? "今日 \(routinesDone)/\(routines.count)"
                         : (project.isComplete ? "✓ \(project.doneCount)/\(project.total)" : "\(project.doneCount)/\(project.total)"))
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                }

                ProgressBar(fraction: routineOnly ? Double(routinesDone) / Double(routines.count) : project.fraction)

                HStack(spacing: 8) {
                    if !routineOnly {
                        Text(percentText(project.fraction))
                    }
                    if today > 0 {
                        Text("今日 +\(today)").foregroundStyle(Theme.accent)
                    }
                    if !routineOnly && !routines.isEmpty {
                        Text("循環 \(routinesDone)/\(routines.count)")
                    }
                    Spacer()
                    Text(relativeDay(project.lastActiveAt, now: now, clock: clock))
                }
                .font(.system(size: 11))
                .monospacedDigit()
                .foregroundStyle(Theme.dim)

                if let nearest {
                    HStack(spacing: 6) {
                        PaceLine(pace: nearest.pace, deadline: nearest.deadline, now: now, detailed: false)
                        // 截止日是某個分組的，就標出是哪一組
                        if nearest.id != project.id, let group = project.groups.first(where: { $0.id == nearest.id }) {
                            Text(group.name)
                                .font(.system(size: 11))
                                .foregroundStyle(Theme.dim)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(12)
            .modifier(CardBackground())
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(hover ? Theme.accent : Color.clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .contextMenu {
            Button("打開") { panel.route = .project(project.id) }
            Button("歸檔") { store.setArchived(project.id, true) }
        }
    }
}
