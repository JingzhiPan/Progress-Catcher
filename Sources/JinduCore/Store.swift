import Combine
import Foundation

/// 全部資料的唯一出入口：介面只讀 `data`，所有修改都走這裡的方法，改完自動存檔。
@MainActor
public final class Store: ObservableObject {
    @Published public private(set) var data: AppData

    /// 資料檔位置；nil 表示只放在記憶體裡（測試和自檢用）。
    public let fileURL: URL?
    private var pendingSave: DispatchWorkItem?

    public static let maxGridCells = 2000

    public init(directory: URL?) {
        if let directory {
            let url = directory.appendingPathComponent("data.json")
            fileURL = url
            data = Persistence.load(from: url)
            Persistence.backUp(url)
        } else {
            fileURL = nil
            data = AppData()
        }
    }

    public var clock: DayClock { DayClock(startHour: data.settings.dayStartHour) }

    public func project(_ id: UUID?) -> Project? {
        guard let id else { return nil }
        return data.projects.first { $0.id == id }
    }

    // MARK: 項目

    @discardableResult
    public func addProject(name: String, now: Date = Date()) -> UUID {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let project = Project(name: trimmed.isEmpty ? "項目 \(data.projects.count + 1)" : trimmed, now: now)
        data.projects.append(project)
        scheduleSave()
        return project.id
    }

    public func renameProject(_ id: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withProject(id) { $0.name = trimmed }
    }

    public func setArchived(_ id: UUID, _ archived: Bool) {
        withProject(id) { $0.archived = archived }
    }

    public func deleteProject(_ id: UUID) {
        guard data.projects.contains(where: { $0.id == id }) else { return }
        data.projects.removeAll { $0.id == id }
        if data.settings.menuBarProjectID == id { data.settings.menuBarProjectID = nil }
        scheduleSave()
    }

    // MARK: 分組

    /// 起止不合法（止 < 起、起 < 0、格子太多）時不新增，回傳 nil。
    @discardableResult
    public func addGridGroup(project pid: UUID, name: String, start: Int, end: Int) -> UUID? {
        guard Self.isValidRange(start: start, end: end) else { return nil }
        var id: UUID?
        withProject(pid) { p in
            let group = TrackGroup(name: Self.groupName(name, fallback: "第 \(p.groups.count + 1) 組"), start: start, end: end)
            p.groups.append(group)
            id = group.id
        }
        return id
    }

    @discardableResult
    public func addListGroup(project pid: UUID, name: String) -> UUID? {
        var id: UUID?
        withProject(pid) { p in
            let group = TrackGroup(name: Self.groupName(name, fallback: "清單 \(p.groups.count + 1)"))
            p.groups.append(group)
            id = group.id
        }
        return id
    }

    public func renameGroup(_ gid: UUID, project pid: UUID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withGroup(gid, in: pid) { $0.name = trimmed }
    }

    @discardableResult
    public func setRange(_ gid: UUID, project pid: UUID, start: Int, end: Int) -> Bool {
        guard Self.isValidRange(start: start, end: end) else { return false }
        withGroup(gid, in: pid) { g in
            g.start = start
            g.end = end
        }
        return true
    }

    public func setCollapsed(_ gid: UUID, project pid: UUID, _ collapsed: Bool) {
        withGroup(gid, in: pid) { $0.collapsed = collapsed }
    }

    public func deleteGroup(_ gid: UUID, project pid: UUID) {
        withProject(pid) { p in
            p.groups.removeAll { $0.id == gid }
            if p.currentGroupID == gid { p.currentGroupID = nil }
        }
    }

    /// 把分組 `gid` 挪到 `target` 現在的位置。
    public func moveGroup(_ gid: UUID, onto target: UUID, project pid: UUID) {
        withProject(pid) { p in
            guard let from = p.groups.firstIndex(where: { $0.id == gid }),
                  let to = p.groups.firstIndex(where: { $0.id == target }), from != to else { return }
            let moved = p.groups.remove(at: from)
            p.groups.insert(moved, at: to)
        }
    }

    public func setCurrentGroup(_ gid: UUID, project pid: UUID) {
        withProject(pid) { p in
            if p.groups.contains(where: { $0.id == gid }) { p.currentGroupID = gid }
        }
    }

    @discardableResult
    public func addRoutineGroup(project pid: UUID, name: String) -> UUID? {
        var id: UUID?
        withProject(pid) { p in
            let group = TrackGroup(name: Self.groupName(name, fallback: "循環任務"), routines: [])
            p.groups.append(group)
            id = group.id
        }
        return id
    }

    // MARK: 截止日

    /// 設定或移除（傳 nil）項目的截止日。
    public func setDeadline(_ date: Date?, project pid: UUID, now: Date = Date()) {
        withProject(pid) { p in
            guard p.deadline != date else { return }
            p.deadline = date
            p.deadlineSetAt = date == nil ? nil : now
        }
    }

    /// 設定或移除（傳 nil）分組的截止日。
    public func setDeadline(_ date: Date?, group gid: UUID, project pid: UUID, now: Date = Date()) {
        withGroup(gid, in: pid) { g in
            guard g.deadline != date else { return }
            g.deadline = date
            g.deadlineSetAt = date == nil ? nil : now
        }
    }

    // MARK: 循環任務

    @discardableResult
    public func addRoutine(_ title: String, rule: RoutineRule, group gid: UUID, project pid: UUID, now: Date = Date()) -> UUID? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, Self.isValidRule(rule) else { return nil }
        var id: UUID?
        withGroup(gid, in: pid) { g in
            guard g.kind == .routine else { return }
            let routine = Routine(title: trimmed, rule: rule, startDate: now)
            g.routines.append(routine)
            id = routine.id
        }
        return id
    }

    /// 點一下循環任務：今天該做還沒做完 → 記一次；已經做完 → 撤銷最近一次。今天沒輪到 → 不動。
    public func tapRoutine(_ rid: UUID, group gid: UUID, project pid: UUID, now: Date = Date()) {
        let clock = self.clock
        withProject(pid) { p in
            guard let gi = p.groups.firstIndex(where: { $0.id == gid }),
                  let ri = p.groups[gi].routines.firstIndex(where: { $0.id == rid }) else { return }
            let state = p.groups[gi].routines[ri].state(now: now, clock: clock)
            guard state.isDueToday else { return }
            if state.isSatisfied {
                Self.removeLatestLog(&p.groups[gi].routines[ri], now: now, clock: clock)
            } else {
                p.groups[gi].routines[ri].log.append(now)
                p.lastActiveAt = now
            }
        }
    }

    /// 撤銷本週期（或今天）最近的一次記錄。
    public func undoRoutine(_ rid: UUID, group gid: UUID, project pid: UUID, now: Date = Date()) {
        let clock = self.clock
        withGroup(gid, in: pid) { g in
            guard let ri = g.routines.firstIndex(where: { $0.id == rid }) else { return }
            Self.removeLatestLog(&g.routines[ri], now: now, clock: clock)
        }
    }

    public func renameRoutine(_ rid: UUID, group gid: UUID, project pid: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withGroup(gid, in: pid) { g in
            if let ri = g.routines.firstIndex(where: { $0.id == rid }) { g.routines[ri].title = trimmed }
        }
    }

    public func deleteRoutine(_ rid: UUID, group gid: UUID, project pid: UUID) {
        withGroup(gid, in: pid) { $0.routines.removeAll { $0.id == rid } }
    }

    private static func removeLatestLog(_ routine: inout Routine, now: Date, clock: DayClock) {
        let today = clock.day(of: now)
        var window = DateInterval(start: today, duration: 86400)
        if case .quota(_, let per) = routine.rule,
           let iv = clock.calendar.dateInterval(of: per == .week ? .weekOfYear : .month, for: today) {
            window = iv
        }
        let inWindow = routine.log.indices.filter {
            let day = clock.day(of: routine.log[$0])
            return day >= window.start && day < window.end
        }
        guard let latest = inWindow.max(by: { routine.log[$0] < routine.log[$1] }) else { return }
        routine.log.remove(at: latest)
    }

    public static func isValidRule(_ rule: RoutineRule) -> Bool {
        switch rule {
        case .daily: return true
        case .weekdays(let days): return !days.isEmpty && days.allSatisfy { (1...7).contains($0) }
        case .quota(let times, _): return (1...31).contains(times)
        case .everyN(let days): return (2...365).contains(days)
        }
    }

    // MARK: 蓋章

    public func setStamp(_ n: Int, done: Bool, group gid: UUID, project pid: UUID, now: Date = Date()) {
        withProject(pid) { p in
            guard let gi = p.groups.firstIndex(where: { $0.id == gid }) else { return }
            guard p.groups[gi].kind == .grid, (p.groups[gi].start...p.groups[gi].end).contains(n) else { return }
            guard p.groups[gi].isDone(n) != done else { return }
            p.groups[gi].stamps[n] = done ? now : nil
            p.lastActiveAt = now
            p.currentGroupID = gid
        }
    }

    // MARK: 清單項

    @discardableResult
    public func addItem(_ title: String, group gid: UUID, project pid: UUID) -> UUID? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var id: UUID?
        withGroup(gid, in: pid) { g in
            guard g.kind == .list else { return }
            let item = ListItem(title: trimmed)
            g.items.append(item)
            id = item.id
        }
        return id
    }

    public func setItemDone(_ iid: UUID, done: Bool, group gid: UUID, project pid: UUID, now: Date = Date()) {
        withProject(pid) { p in
            guard let gi = p.groups.firstIndex(where: { $0.id == gid }),
                  let ii = p.groups[gi].items.firstIndex(where: { $0.id == iid }) else { return }
            guard (p.groups[gi].items[ii].doneAt != nil) != done else { return }
            p.groups[gi].items[ii].doneAt = done ? now : nil
            p.lastActiveAt = now
            p.currentGroupID = gid
        }
    }

    public func renameItem(_ iid: UUID, group gid: UUID, project pid: UUID, to title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withGroup(gid, in: pid) { g in
            if let ii = g.items.firstIndex(where: { $0.id == iid }) { g.items[ii].title = trimmed }
        }
    }

    public func deleteItem(_ iid: UUID, group gid: UUID, project pid: UUID) {
        withGroup(gid, in: pid) { $0.items.removeAll { $0.id == iid } }
    }

    public func moveItem(_ iid: UUID, onto target: UUID, group gid: UUID, project pid: UUID) {
        withGroup(gid, in: pid) { g in
            guard let from = g.items.firstIndex(where: { $0.id == iid }),
                  let to = g.items.firstIndex(where: { $0.id == target }), from != to else { return }
            let moved = g.items.remove(at: from)
            g.items.insert(moved, at: to)
        }
    }

    // MARK: 設定

    public func setDayStartHour(_ hour: Int) {
        let clamped = min(max(hour, 0), 23)
        guard data.settings.dayStartHour != clamped else { return }
        data.settings.dayStartHour = clamped
        scheduleSave()
    }

    public func setMenuBarProject(_ id: UUID?) {
        guard data.settings.menuBarProjectID != id else { return }
        data.settings.menuBarProjectID = id
        scheduleSave()
    }

    public func setReminder(_ mode: ReminderMode) {
        guard data.settings.reminder != mode else { return }
        data.settings.reminder = mode
        scheduleSave()
    }

    public func setNotifyTime(hour: Int, minute: Int) {
        let h = min(max(hour, 0), 23), m = min(max(minute, 0), 59)
        guard data.settings.notifyHour != h || data.settings.notifyMinute != m else { return }
        data.settings.notifyHour = h
        data.settings.notifyMinute = m
        scheduleSave()
    }

    // MARK: 匯出／匯入

    public enum ImportError: Error, Equatable {
        /// 不是這個 app 匯出的檔案
        case notRecognized
    }

    public func exportData() throws -> Data {
        try Persistence.encoder().encode(data)
    }

    /// 用檔案內容取代現有的全部資料。取代前會把現有資料另存一份到 backups/。
    public func importData(_ raw: Data, now: Date = Date()) throws {
        // 先確認檔案裡真的有 projects，免得一個不相干的 JSON 把資料清空。
        struct Probe: Decodable { let projects: [Project] }
        guard (try? Persistence.decoder().decode(Probe.self, from: raw)) != nil,
              let incoming = try? Persistence.decoder().decode(AppData.self, from: raw) else {
            throw ImportError.notRecognized
        }
        if let fileURL {
            flush()
            let dir = fileURL.deletingLastPathComponent().appendingPathComponent("backups")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let name = "匯入前-\(Int(now.timeIntervalSince1970)).json"
            try? Persistence.save(data, to: dir.appendingPathComponent(name))
        }
        data = incoming
        scheduleSave()
    }

    // MARK: 存檔

    /// 立刻把還沒寫出去的修改存檔（關面板、退出前呼叫）。
    public func flush() {
        guard pendingSave != nil else { return }
        pendingSave?.cancel()
        pendingSave = nil
        writeNow()
    }

    private func scheduleSave() {
        guard fileURL != nil else { return }
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.pendingSave = nil
                self?.writeNow()
            }
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    private func writeNow() {
        guard let fileURL else { return }
        do {
            try Persistence.save(data, to: fileURL)
        } catch {
            NSLog("進度表：存檔失敗 \(error.localizedDescription)")
        }
    }

    // MARK: 內部

    private func withProject(_ pid: UUID, _ body: (inout Project) -> Void) {
        guard let i = data.projects.firstIndex(where: { $0.id == pid }) else { return }
        var project = data.projects[i]
        body(&project)
        guard project != data.projects[i] else { return }
        data.projects[i] = project
        scheduleSave()
    }

    private func withGroup(_ gid: UUID, in pid: UUID, _ body: (inout TrackGroup) -> Void) {
        withProject(pid) { p in
            guard let gi = p.groups.firstIndex(where: { $0.id == gid }) else { return }
            body(&p.groups[gi])
        }
    }

    public static func isValidRange(start: Int, end: Int) -> Bool {
        start >= 0 && end >= start && end - start < maxGridCells
    }

    private static func groupName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }
}

/// 讀寫 data.json，外加每日備份。
public enum Persistence {
    static func encoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }

    static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    public static func save(_ data: AppData, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder().encode(data).write(to: url, options: .atomic)
    }

    /// 檔案不存在 → 空資料。檔案讀不懂 → 把它改名留底，絕不覆蓋，再從空資料開始。
    public static func load(from url: URL) -> AppData {
        guard let raw = try? Data(contentsOf: url) else { return AppData() }
        do {
            return try decoder().decode(AppData.self, from: raw)
        } catch {
            let stamp = Int(Date().timeIntervalSince1970)
            let aside = url.deletingLastPathComponent().appendingPathComponent("data-讀不懂-\(stamp).json")
            try? FileManager.default.moveItem(at: url, to: aside)
            NSLog("進度表：資料檔讀不懂，已另存為 \(aside.lastPathComponent)：\(error)")
            return AppData()
        }
    }

    /// 每天第一次啟動時把 data.json 複製一份到 backups/，只留最近 10 份。
    public static func backUp(_ url: URL, now: Date = Date()) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return }
        let dir = url.deletingLastPathComponent().appendingPathComponent("backups")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        let target = dir.appendingPathComponent("data-\(f.string(from: now)).json")
        if !fm.fileExists(atPath: target.path) {
            try? fm.copyItem(at: url, to: target)
        }
        let all = ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("data-") && $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in all.dropFirst(10) { try? fm.removeItem(at: old) }
    }
}
