import JinduCore
import SwiftUI

/// 「11/20」；不是今年就帶年份。
func shortDate(_ date: Date, now: Date) -> String {
    let cal = Calendar.current
    let c = cal.dateComponents([.year, .month, .day], from: date)
    let sameYear = c.year == cal.component(.year, from: now)
    return sameYear ? "\(c.month ?? 0)/\(c.day ?? 0)" : "\(c.year ?? 0)/\(c.month ?? 0)/\(c.day ?? 0)"
}

func weekdayName(_ date: Date) -> String {
    ["週日", "週一", "週二", "週三", "週四", "週五", "週六"][Calendar.current.component(.weekday, from: date) - 1]
}

/// 配速的一行字。`detailed` 為 false 時給首頁卡片用，短一點。
func paceText(_ pace: Pace, deadline: Date, now: Date, detailed: Bool) -> String {
    let due = shortDate(deadline, now: now)
    switch pace.status {
    case .complete:
        return "截止 \(due) · 已完成"
    case .overdue:
        return "已過期 \(1 - pace.daysLeft) 天 · 還剩 \(pace.remaining)"
    case .behind, .onTrack:
        var parts: [String] = []
        if pace.status == .behind { parts.append("落後 \(pace.lag)") }
        parts.append(pace.daysLeft == 1 ? "今天截止" : "截止 \(due)")
        if detailed {
            parts.append("剩 \(pace.remaining)")
            if pace.daysLeft > 1 { parts.append("\(pace.daysLeft) 天") }
        }
        parts.append("每天 \(pace.perDay)")
        if detailed { parts.append("今日 \(pace.doneToday)/\(pace.perDay)") }
        return parts.joined(separator: " · ")
    }
}

struct PaceLine: View {
    let pace: Pace
    let deadline: Date
    let now: Date
    var detailed = true

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: pace.status == .complete ? "flag.checkered" : "flag")
                .font(.system(size: 9, weight: .medium))
            Text(paceText(pace, deadline: deadline, now: now, detailed: detailed))
                .font(.system(size: 11))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
        .foregroundStyle(pace.needsAttention ? Theme.danger : Theme.dim)
    }
}

/// 設定／修改／移除截止日。用步進式日期欄而不是彈出月曆：
/// 彈出月曆是另一個視窗，會讓未置頂的面板以為「點到別處了」而收起。
struct DeadlineEditor: View {
    let current: Date?
    let onCommit: (Date?) -> Void
    let onCancel: () -> Void
    @State private var date: Date

    init(current: Date?, onCommit: @escaping (Date?) -> Void, onCancel: @escaping () -> Void) {
        self.current = current
        self.onCommit = onCommit
        self.onCancel = onCancel
        let fallback = Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date()
        _date = State(initialValue: current ?? fallback)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("截止日").font(.system(size: 11)).foregroundStyle(Theme.dim)
                DatePicker("", selection: $date, displayedComponents: .date)
                    .datePickerStyle(.stepperField)
                    .labelsHidden()
                    .fixedSize()
                Text(weekdayName(date)).font(.system(size: 11)).foregroundStyle(Theme.dim)
                Spacer()
            }
            HStack(spacing: 6) {
                if current != nil {
                    Button("移除截止日") { onCommit(nil) }.buttonStyle(PillButtonStyle(kind: .danger))
                }
                Spacer()
                Button("取消", action: onCancel).buttonStyle(PillButtonStyle(kind: .quiet))
                Button("好") { onCommit(Calendar.current.startOfDay(for: date)) }.buttonStyle(PillButtonStyle())
            }
        }
    }
}
