import JinduCore
import SwiftUI

func ruleLabel(_ rule: RoutineRule) -> String {
    switch rule {
    case .daily:
        return "每天"
    case .weekdays(let days):
        let set = Set(days)
        if set.count == 7 { return "每天" }
        if set == [2, 3, 4, 5, 6] { return "工作日" }
        if set == [1, 7] { return "週末" }
        let names = [1: "日", 2: "一", 3: "二", 4: "三", 5: "四", 6: "五", 7: "六"]
        return "週" + [2, 3, 4, 5, 6, 7, 1].filter(set.contains).compactMap { names[$0] }.joined()
    case .quota(let times, let per):
        return per == .week ? "每週 \(times) 次" : "每月 \(times) 次"
    case .everyN(let days):
        return "每 \(days) 天"
    }
}

/// 循環任務前面那個勾選框。按日排的是方框；「做夠 N 次」型顯示「1/3」。
struct RoutineCheck: View {
    let rule: RoutineRule
    let state: RoutineState

    var body: some View {
        if case .quota = rule {
            Text(state.isSatisfied ? "✓ \(state.done)/\(state.target)" : "\(state.done)/\(state.target)")
                .font(.system(size: 10, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(state.isSatisfied ? Theme.onAccent : Theme.accent)
                .padding(.horizontal, 6)
                .frame(minWidth: 30, minHeight: 17)
                .background(state.isSatisfied ? Theme.accent : Theme.accentSoft, in: Capsule())
        } else {
            RoundedRectangle(cornerRadius: 4)
                .fill(state.isSatisfied ? Theme.accent : Theme.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(state.isSatisfied ? Theme.accent : Theme.border,
                                      style: StrokeStyle(lineWidth: 1.2, dash: state.isDueToday ? [] : [2.5, 2]))
                )
                .overlay {
                    if state.isSatisfied {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                    }
                }
                .frame(width: 15, height: 15)
        }
    }
}

/// 最近幾次做沒做：實心＝做了，空心＝漏了，最右邊最新。
struct HistoryDots: View {
    let history: [Bool]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(history.enumerated()), id: \.offset) { _, done in
                Circle()
                    .fill(done ? Theme.accent.opacity(0.75) : Color.clear)
                    .overlay(Circle().strokeBorder(done ? Color.clear : Theme.border, lineWidth: 1))
                    .frame(width: 6, height: 6)
            }
        }
        .help("最近 \(history.count) 次：做了 \(history.filter { $0 }.count) 次")
    }
}

/// 循環任務分組的內容：一行一個任務，底下是新增表單。
struct RoutineBody: View {
    let projectID: UUID
    let group: TrackGroup
    let now: Date
    var showsAddForm = true
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(group.routines) { routine in
                RoutineRow(projectID: projectID, groupID: group.id, routine: routine,
                           state: routine.state(now: now, clock: store.clock), now: now)
            }

            if showsAddForm {
                AddRoutineForm(projectID: projectID, groupID: group.id)
                    .padding(.top, group.routines.isEmpty ? 0 : 8)
            } else if group.routines.isEmpty {
                Text("這裡還沒有循環任務。")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }
        }
    }
}

private struct RoutineRow: View {
    let projectID: UUID
    let groupID: UUID
    let routine: Routine
    let state: RoutineState
    let now: Date
    @EnvironmentObject var store: Store
    @State private var renaming = false
    @State private var draft = ""
    @FocusState private var renameFocused: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            RoutineCheck(rule: routine.rule, state: state)
                .probe("routine-\(routine.title)")

            VStack(alignment: .leading, spacing: 2) {
                if renaming {
                    TextField("內容", text: $draft)
                        .modifier(FieldStyle())
                        .focused($renameFocused)
                        .onSubmit {
                            store.renameRoutine(routine.id, group: groupID, project: projectID, to: draft)
                            renaming = false
                        }
                        .onExitCommand { renaming = false }
                } else {
                    Text(routine.title)
                        .font(.system(size: 12.5))
                        .strikethrough(isScheduledDone, color: Theme.dim)
                        .foregroundStyle(isScheduledDone ? Theme.dim : Theme.fg)
                        .lineLimit(2)
                }
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(Theme.dim)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            if !state.history.isEmpty {
                HistoryDots(history: state.history)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 2)
        .opacity(state.isDueToday ? 1 : 0.6)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !renaming else { return }
            store.tapRoutine(routine.id, group: groupID, project: projectID)
        }
        .contextMenu {
            Button("重新命名") {
                draft = routine.title
                renaming = true
                renameFocused = true
            }
            if state.done > 0 {
                Button("撤銷一次") { store.undoRoutine(routine.id, group: groupID, project: projectID) }
            }
            Button("刪除") { store.deleteRoutine(routine.id, group: groupID, project: projectID) }
        }
    }

    /// 按日排的任務做完後劃掉；「做夠 N 次」型看前面的數字就夠了。
    private var isScheduledDone: Bool {
        if case .quota = routine.rule { return false }
        return state.isSatisfied
    }

    private var subtitle: String {
        var parts = [ruleLabel(routine.rule)]
        if !state.isDueToday {
            if let next = state.nextDue {
                parts.append("下次 \(shortDate(next, now: now))（\(weekdayName(next))）")
            } else {
                parts.append("今天沒輪到")
            }
        }
        if state.streak >= 2 { parts.append("連續 \(state.streak)") }
        return parts.joined(separator: " · ")
    }
}

/// 新增循環任務：名字加頻率。
private struct AddRoutineForm: View {
    let projectID: UUID
    let groupID: UUID
    @EnvironmentObject var store: Store
    @State private var title = ""
    @State private var frequency: Frequency = .daily
    @State private var days: Set<Int> = [2, 3, 4, 5, 6]
    @State private var times = 3
    @State private var interval = 3
    @FocusState private var titleFocused: Bool

    private enum Frequency: String, CaseIterable, Identifiable {
        case daily = "每天"
        case weekdays = "每週固定幾天"
        case weekly = "每週做夠 N 次"
        case monthly = "每月做夠 N 次"
        case everyN = "每隔 N 天"
        var id: String { rawValue }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                TextField("新增循環任務", text: $title)
                    .modifier(FieldStyle())
                    .focused($titleFocused)
                    .onSubmit(add)
                Button("添加", action: add)
                    .buttonStyle(PillButtonStyle())
            }

            HStack(spacing: 8) {
                Menu {
                    ForEach(Frequency.allCases) { option in
                        Button(option.rawValue) { frequency = option }
                    }
                } label: {
                    Text(frequency.rawValue).font(.system(size: 11))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()

                switch frequency {
                case .daily:
                    EmptyView()
                case .weekdays:
                    WeekdayChips(days: $days)
                case .weekly:
                    MiniStepper(value: $times, range: 1...7, unit: "次")
                case .monthly:
                    MiniStepper(value: $times, range: 1...31, unit: "次")
                case .everyN:
                    MiniStepper(value: $interval, range: 2...90, unit: "天")
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var rule: RoutineRule {
        switch frequency {
        case .daily: return .daily
        case .weekdays: return .weekdays(days.sorted())
        case .weekly: return .quota(times: min(times, 7), per: .week)
        case .monthly: return .quota(times: times, per: .month)
        case .everyN: return .everyN(days: interval)
        }
    }

    private func add() {
        guard store.addRoutine(title, rule: rule, group: groupID, project: projectID) != nil else {
            titleFocused = true
            return
        }
        title = ""
        titleFocused = true
    }
}

/// 一二三四五六日 七個小圓鈕。
private struct WeekdayChips: View {
    @Binding var days: Set<Int>
    private let order: [(Int, String)] = [(2, "一"), (3, "二"), (4, "三"), (5, "四"), (6, "五"), (7, "六"), (1, "日")]

    var body: some View {
        HStack(spacing: 3) {
            ForEach(order, id: \.0) { weekday, name in
                let on = days.contains(weekday)
                Button {
                    if on { days.remove(weekday) } else { days.insert(weekday) }
                } label: {
                    Text(name)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(on ? Theme.onAccent : Theme.dim)
                        .frame(width: 21, height: 21)
                        .background(on ? Theme.accent : Theme.border.opacity(0.5), in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct MiniStepper: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    let unit: String

    var body: some View {
        HStack(spacing: 2) {
            IconButton(symbol: "minus", help: "少一點") { value = max(range.lowerBound, value - 1) }
            Text("\(min(max(value, range.lowerBound), range.upperBound)) \(unit)")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .frame(minWidth: 38)
            IconButton(symbol: "plus", help: "多一點") { value = min(range.upperBound, value + 1) }
        }
        .onAppear { value = min(max(value, range.lowerBound), range.upperBound) }
    }
}

/// 首頁最上面的「今天」：今天輪到的循環任務，直接在這裡勾。
struct TodaySection: View {
    let items: [TodayRoutine]
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack {
                Text("今天").font(.system(size: 12, weight: .bold))
                Spacer()
                Text("\(items.filter(\.state.isSatisfied).count)/\(items.count)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.accent)
            }
            .padding(.bottom, 5)

            ForEach(items) { item in
                HStack(spacing: 8) {
                    RoutineCheck(rule: item.routine.rule, state: item.state)
                        .probe("today-\(item.routine.title)")
                    Text(item.routine.title)
                        .font(.system(size: 12.5))
                        .strikethrough(item.state.isSatisfied, color: Theme.dim)
                        .foregroundStyle(item.state.isSatisfied ? Theme.dim : Theme.fg)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(item.projectName)
                        .font(.system(size: 10.5))
                        .foregroundStyle(Theme.dim)
                        .lineLimit(1)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture {
                    store.tapRoutine(item.routine.id, group: item.groupID, project: item.projectID)
                }
            }
        }
        .padding(12)
        .modifier(CardBackground())
    }
}
