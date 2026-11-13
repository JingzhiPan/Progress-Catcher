import JinduCore
import SwiftUI

/// 迷你條：只留正在做的那一組，盡量不擋稿子。
struct MiniView: View {
    @EnvironmentObject var store: Store
    @EnvironmentObject var panel: PanelController

    var body: some View {
        let project = store.project(panel.miniProjectID).flatMap { $0.archived ? nil : $0 } ?? store.data.focusProject
        let group = project?.currentGroup
        let now = Date()

        VStack(spacing: 0) {
            HeaderBar(height: 32) {
                HStack(spacing: 6) {
                    Text(group?.name ?? project?.name ?? "進度表")
                        .font(.system(size: 12, weight: .bold))
                        .lineLimit(1)
                    if group != nil, let project {
                        Text(project.name)
                            .font(.system(size: 10.5))
                            .foregroundStyle(Theme.dim)
                            .lineLimit(1)
                    }
                }
                .allowsHitTesting(false)
            } trailing: {
                if let group, group.kind != .routine {
                    Text(group.isComplete ? "✓ \(group.doneCount)/\(group.total)" : "\(group.doneCount)/\(group.total)")
                        .font(.system(size: 11, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(Theme.accent)
                        .padding(.trailing, 2)
                        .allowsHitTesting(false)
                }
                if let project, let group, project.groups.count > 1 {
                    IconButton(symbol: "chevron.left", help: "上一組") { step(-1, in: project, from: group) }
                    IconButton(symbol: "chevron.right", help: "下一組") { step(1, in: project, from: group) }
                }
                IconButton(symbol: "rectangle.expand.vertical", help: "展開完整面板") { panel.setMini(false) }
            }

            if let project, let group {
                ScrollViewReader { proxy in
                    ScrollView {
                        Group {
                            switch group.kind {
                            case .grid:
                                GridCells(group: group, scrollProxy: proxy) { n, done in
                                    store.setStamp(n, done: done, group: group.id, project: project.id)
                                }
                            case .list:
                                ListBody(projectID: project.id, group: group, showsAddField: false)
                            case .routine:
                                RoutineBody(projectID: project.id, group: group, now: now, showsAddForm: false)
                            }
                        }
                        .padding(8)
                    }
                    // 迷你條地方小，不讓捲軸佔寬度（滾輪照樣能捲）
                    .scrollIndicators(.never)
                }
                .id(group.id)
            } else {
                Text(project == nil ? "還沒有項目，展開面板新增一個。" : "這個項目還沒有分組。")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func step(_ delta: Int, in project: Project, from group: TrackGroup) {
        guard let i = project.groups.firstIndex(where: { $0.id == group.id }) else { return }
        let count = project.groups.count
        let next = project.groups[(i + delta + count) % count]
        store.setCurrentGroup(next.id, project: project.id)
    }
}
