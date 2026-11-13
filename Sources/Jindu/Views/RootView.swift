import JinduCore
import SwiftUI

struct RootView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var panel: PanelController

    var body: some View {
        Group {
            if panel.mini {
                MiniView()
            } else {
                switch panel.route {
                case .home:
                    HomeView()
                case .project(let id):
                    ProjectView(projectID: id)
                        .id(id)
                case .settings:
                    SettingsView()
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .font(.system(size: 13))
        .foregroundStyle(Theme.fg)
        .background(Theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
    }
}

/// 最近 N 天每天做了多少的小柱狀圖，最右邊是今天。
struct DayBars: View {
    let history: [DayCount]
    var height: CGFloat = 26

    var body: some View {
        let peak = max(1, history.map(\.count).max() ?? 1)
        HStack(alignment: .bottom, spacing: 3) {
            ForEach(Array(history.enumerated()), id: \.offset) { index, day in
                RoundedRectangle(cornerRadius: 2)
                    .fill(color(day, isToday: index == history.count - 1))
                    .frame(height: day.count == 0 ? 3 : max(5, height * CGFloat(day.count) / CGFloat(peak)))
                    .frame(maxWidth: .infinity)
                    .help("\(Self.label(day.day))：\(day.count)")
            }
        }
        .frame(height: height, alignment: .bottom)
    }

    private func color(_ day: DayCount, isToday: Bool) -> Color {
        if day.count == 0 { return Theme.border }
        return isToday ? Theme.accent : Theme.accent.opacity(0.5)
    }

    private static func label(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.month, .day], from: date)
        return "\(c.month ?? 0) 月 \(c.day ?? 0) 日"
    }
}

/// 「今天 / 昨天 / N 天前」
func relativeDay(_ date: Date, now: Date, clock: DayClock) -> String {
    switch clock.daysBetween(date, now) {
    case ...0: return "今天"
    case 1: return "昨天"
    case let n: return "\(n) 天前"
    }
}

func percentText(_ fraction: Double) -> String {
    "\(Int((fraction * 100).rounded(.down)))%"
}
