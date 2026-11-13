import JinduCore
import SwiftUI

/// 項目頁裡的一個分組：表頭（名字、範圍、進度、選單）加上格子或清單。
struct GroupCard: View {
    let projectID: UUID
    let group: TrackGroup
    @Binding var dragging: UUID?
    @EnvironmentObject var store: Store
    @State private var mode: Mode = .normal
    @State private var draftName = ""
    @State private var draftStart = ""
    @State private var draftEnd = ""
    @FocusState private var editFocused: Bool

    private enum Mode { case normal, rename, range, confirmDelete }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if mode == .range { rangeEditor }
            if mode == .confirmDelete { deleteRow }

            if !group.collapsed {
                switch group.kind {
                case .grid:
                    GridCells(group: group) { n, done in
                        store.setStamp(n, done: done, group: group.id, project: projectID)
                    }
                case .list:
                    ListBody(projectID: projectID, group: group)
                }
            }
        }
        .padding(12)
        .modifier(CardBackground())
        .opacity(dragging == group.id ? 0.6 : 1)
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(Theme.dim.opacity(0.7))
                .frame(width: 14, height: 20)
                .contentShape(Rectangle())
                .help("按住拖動排序")
                .onDrag {
                    dragging = group.id
                    return NSItemProvider(object: group.id.uuidString as NSString)
                }

            if mode == .rename {
                TextField("分組名稱", text: $draftName)
                    .modifier(FieldStyle())
                    .focused($editFocused)
                    .onSubmit {
                        store.renameGroup(group.id, project: projectID, to: draftName)
                        mode = .normal
                    }
                    .onExitCommand { mode = .normal }
            } else {
                Button {
                    store.setCollapsed(group.id, project: projectID, !group.collapsed)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: group.collapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.dim)
                            .frame(width: 10)
                        Text(group.name)
                            .font(.system(size: 13, weight: .bold))
                            .lineLimit(1)
                        if group.kind == .grid {
                            Text("\(group.start)–\(group.end)")
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(Theme.dim)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(group.collapsed ? "展開" : "收起")
            }

            Spacer(minLength: 6)

            Text(group.isComplete ? "✓ \(group.doneCount)/\(group.total)" : "\(group.doneCount)/\(group.total)")
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(Theme.accent)

            MoreMenu {
                Button("重新命名") {
                    draftName = group.name
                    mode = .rename
                    editFocused = true
                }
                if group.kind == .grid {
                    Button("修改範圍") {
                        draftStart = String(group.start)
                        draftEnd = String(group.end)
                        mode = .range
                    }
                }
                Divider()
                Button("刪除分組…") { mode = .confirmDelete }
            }
        }
    }

    private var rangeEditor: some View {
        HStack(spacing: 6) {
            Text("範圍").font(.system(size: 11)).foregroundStyle(Theme.dim)
            TextField("起", text: $draftStart)
                .modifier(FieldStyle())
                .frame(width: 56)
                .onSubmit(commitRange)
                .onChange(of: draftStart) { _, v in draftStart = v.digitsOnly }
            Text("–").foregroundStyle(Theme.dim)
            TextField("止", text: $draftEnd)
                .modifier(FieldStyle())
                .frame(width: 56)
                .onSubmit(commitRange)
                .onChange(of: draftEnd) { _, v in draftEnd = v.digitsOnly }
            Spacer()
            Button("取消") { mode = .normal }.buttonStyle(PillButtonStyle(kind: .quiet))
            Button("好", action: commitRange).buttonStyle(PillButtonStyle())
        }
    }

    private func commitRange() {
        guard let s = Int(draftStart), let e = Int(draftEnd) else { return }
        if store.setRange(group.id, project: projectID, start: s, end: e) { mode = .normal }
    }

    private var deleteRow: some View {
        HStack(spacing: 8) {
            Text("刪除這個分組和它的記錄？")
                .font(.system(size: 12))
                .foregroundStyle(Theme.danger)
            Spacer()
            Button("取消") { mode = .normal }.buttonStyle(PillButtonStyle(kind: .quiet))
            Button("刪除") { store.deleteGroup(group.id, project: projectID) }
                .buttonStyle(PillButtonStyle(kind: .danger))
        }
    }
}

/// 自檢時用來記下每組格子在視窗裡的位置，平時不啟用。
@MainActor
enum DebugProbe {
    static var enabled = false
    static var gridFrames: [UUID: CGRect] = [:]
}

/// 一排排編號格子。點一下蓋章／取消；按住拖過去可以連續蓋（或連續取消，看第一格原本的狀態）。
struct GridCells: View {
    let group: TrackGroup
    /// 給了就會自動捲到第一個還沒蓋的那一排（迷你條用）。
    var scrollProxy: ScrollViewProxy?
    let onSet: (Int, Bool) -> Void

    @State private var width: CGFloat = 0
    @State private var hovered: Int?
    @State private var paintValue: Bool?
    @State private var lastPoint: CGPoint?

    private let minCell: CGFloat = 32
    private let gap: CGFloat = 4

    var body: some View {
        let m = metrics
        // 佔位的透明塊決定大小，格子畫在它的 overlay 上：
        // 這樣格子本身的寬度不會反過來撐住版面，視窗拉窄時才能跟著重排。
        Color.clear
            .frame(maxWidth: .infinity)
            .frame(height: width > 0 ? m.height : 1)
            .overlay(alignment: .topLeading) {
                if width > 0 {
                    VStack(alignment: .leading, spacing: gap) {
                        ForEach(0..<m.rows, id: \.self) { row in
                            HStack(spacing: gap) {
                                ForEach(m.indices(inRow: row), id: \.self) { i in
                                    cell(i, size: m.cell)
                                }
                            }
                            .id(rowID(row))
                        }
                    }
                    .fixedSize()
                }
            }
        .background(GeometryReader { geo in
            Color.clear
                .onAppear { measured(geo.frame(in: .global)) }
                .onChange(of: geo.frame(in: .global)) { _, frame in measured(frame) }
        })
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0, coordinateSpace: .local)
                .onChanged { paint(to: $0.location) }
                .onEnded { _ in
                    paintValue = nil
                    lastPoint = nil
                }
        )
        .onContinuousHover { phase in
            switch phase {
            case .active(let p): hovered = metrics.index(at: p)
            case .ended: hovered = nil
            }
        }
        .onChange(of: width) { _, _ in scrollToFirstUndone(animated: false) }
        .onChange(of: group.id) { _, _ in scrollToFirstUndone(animated: false) }
        .onChange(of: firstUndoneRow) { _, _ in scrollToFirstUndone(animated: true) }
    }

    private var metrics: GridMetrics {
        GridMetrics(width: width, count: group.total, minCell: minCell, gap: gap)
    }

    private var firstUndoneRow: Int? {
        guard width > 0, let i = group.firstUndoneIndex else { return nil }
        return metrics.row(of: i)
    }

    private func rowID(_ row: Int) -> String { "\(group.id.uuidString)-\(row)" }

    private func cell(_ i: Int, size: CGFloat) -> some View {
        let n = group.start + i
        let done = group.isDone(n)
        return Text(String(n))
            .font(.system(size: 10.5, weight: .medium))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .foregroundStyle(done ? Theme.onAccent : Theme.dim)
            .frame(width: size, height: size)
            .background(done ? Theme.accent : Theme.surface, in: RoundedRectangle(cornerRadius: 5))
            .overlay(
                RoundedRectangle(cornerRadius: 5)
                    .strokeBorder(done || hovered == i ? Theme.accent : Theme.border, lineWidth: 1.2)
            )
    }

    private func measured(_ frame: CGRect) {
        if abs(frame.width - width) > 0.5 { width = frame.width }
        if DebugProbe.enabled { DebugProbe.gridFrames[group.id] = frame }
    }

    private func paint(to point: CGPoint) {
        let m = metrics
        // 滑鼠移得快時兩次取樣之間會跳過格子，沿路補點。
        var points = [point]
        if let last = lastPoint {
            let distance = hypot(point.x - last.x, point.y - last.y)
            let steps = max(1, Int(distance / (m.cell / 2)))
            points = (1...steps).map { step in
                let t = CGFloat(step) / CGFloat(steps)
                return CGPoint(x: last.x + (point.x - last.x) * t, y: last.y + (point.y - last.y) * t)
            }
        }
        lastPoint = point

        for p in points {
            guard let i = m.index(at: p) else { continue }
            let n = group.start + i
            // 第一格決定這一筆是「蓋」還是「取消」
            if paintValue == nil { paintValue = !group.isDone(n) }
            if let value = paintValue { onSet(n, value) }
        }
    }

    private func scrollToFirstUndone(animated: Bool) {
        guard let scrollProxy, let row = firstUndoneRow else { return }
        let id = rowID(row)
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeInOut(duration: 0.2)) { scrollProxy.scrollTo(id, anchor: .top) }
            } else {
                scrollProxy.scrollTo(id, anchor: .top)
            }
        }
    }
}

/// 有名字的清單：點一行勾掉，底下輸入框連續新增。
struct ListBody: View {
    let projectID: UUID
    let group: TrackGroup
    var showsAddField = true
    @EnvironmentObject var store: Store
    @State private var newTitle = ""
    @State private var draggingItem: UUID?
    @State private var renamingID: UUID?
    @State private var draftTitle = ""
    @FocusState private var addFocused: Bool
    @FocusState private var renameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            ForEach(group.items) { item in
                row(item)
                    .onDrop(of: [.text], delegate: ReorderDropDelegate(target: item.id, dragging: $draggingItem) { from, to in
                        store.moveItem(from, onto: to, group: group.id, project: projectID)
                    })
            }

            if showsAddField {
                TextField("新增一項，按 Enter", text: $newTitle)
                    .modifier(FieldStyle())
                    .focused($addFocused)
                    .onSubmit(add)
                    .padding(.top, group.items.isEmpty ? 0 : 7)
            } else if group.items.isEmpty {
                Text("這個清單還是空的。")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.dim)
            }
        }
    }

    private func row(_ item: ListItem) -> some View {
        let done = item.doneAt != nil
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            RoundedRectangle(cornerRadius: 4)
                .fill(done ? Theme.accent : Theme.surface)
                .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(done ? Theme.accent : Theme.border, lineWidth: 1.2))
                .overlay {
                    if done {
                        Image(systemName: "checkmark")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(Theme.onAccent)
                    }
                }
                .frame(width: 15, height: 15)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 3 }

            if renamingID == item.id {
                TextField("內容", text: $draftTitle)
                    .modifier(FieldStyle())
                    .focused($renameFocused)
                    .onSubmit {
                        store.renameItem(item.id, group: group.id, project: projectID, to: draftTitle)
                        renamingID = nil
                    }
                    .onExitCommand { renamingID = nil }
            } else {
                Text(item.title)
                    .font(.system(size: 12.5))
                    .strikethrough(done, color: Theme.dim)
                    .foregroundStyle(done ? Theme.dim : Theme.fg)
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            guard renamingID != item.id else { return }
            store.setItemDone(item.id, done: !done, group: group.id, project: projectID)
        }
        .onDrag {
            draggingItem = item.id
            return NSItemProvider(object: item.id.uuidString as NSString)
        }
        .contextMenu {
            Button("重新命名") {
                draftTitle = item.title
                renamingID = item.id
                renameFocused = true
            }
            Button("刪除") { store.deleteItem(item.id, group: group.id, project: projectID) }
        }
    }

    private func add() {
        guard store.addItem(newTitle, group: group.id, project: projectID) != nil else { return }
        newTitle = ""
        addFocused = true
    }
}
