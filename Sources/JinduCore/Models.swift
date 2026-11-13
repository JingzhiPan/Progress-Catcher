import Foundation

/// 分組的形態。之後的「循環任務」會加在這裡。
public enum GroupKind: String, Codable, Sendable {
    /// 一段編號範圍，逐格蓋章（頁碼、集數、題號……）
    case grid
    /// 有名字的清單，逐項勾掉
    case list
    /// 循環任務：按頻率反覆出現，沒有「總數」
    case routine
}

public struct ListItem: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var title: String
    public var doneAt: Date?

    public init(id: UUID = UUID(), title: String, doneAt: Date? = nil) {
        self.id = id
        self.title = title
        self.doneAt = doneAt
    }
}

public struct TrackGroup: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var kind: GroupKind
    /// 只對 grid 有意義：起止編號（含兩端）
    public var start: Int
    public var end: Int
    /// 只對 grid 有意義：編號 → 蓋章時間。範圍改小後，範圍外的章留著但不計數，改回來還在。
    public var stamps: [Int: Date]
    /// 只對 list 有意義
    public var items: [ListItem]
    /// 只對 routine 有意義
    public var routines: [Routine]
    public var collapsed: Bool
    /// 截止日：那一天結束前做完
    public var deadline: Date?
    /// 截止日是哪天設的，配速的均速線從這天起算
    public var deadlineSetAt: Date?

    public init(id: UUID = UUID(), name: String, start: Int, end: Int) {
        self.id = id
        self.name = name
        self.kind = .grid
        self.start = start
        self.end = end
        self.stamps = [:]
        self.items = []
        self.routines = []
        self.collapsed = false
        self.deadline = nil
        self.deadlineSetAt = nil
    }

    public init(id: UUID = UUID(), name: String, items: [ListItem] = []) {
        self.id = id
        self.name = name
        self.kind = .list
        self.start = 1
        self.end = 1
        self.stamps = [:]
        self.items = items
        self.routines = []
        self.collapsed = false
        self.deadline = nil
        self.deadlineSetAt = nil
    }

    public init(id: UUID = UUID(), name: String, routines: [Routine]) {
        self.id = id
        self.name = name
        self.kind = .routine
        self.start = 1
        self.end = 1
        self.stamps = [:]
        self.items = []
        self.routines = routines
        self.collapsed = false
        self.deadline = nil
        self.deadlineSetAt = nil
    }

    public var total: Int {
        switch kind {
        case .grid: return max(0, end - start + 1)
        case .list: return items.count
        case .routine: return 0
        }
    }

    public var doneCount: Int {
        switch kind {
        case .grid: return stamps.keys.reduce(0) { $0 + ((start...end).contains($1) ? 1 : 0) }
        case .list: return items.reduce(0) { $0 + ($1.doneAt == nil ? 0 : 1) }
        case .routine: return 0
        }
    }

    public var isComplete: Bool { total > 0 && doneCount == total }

    /// 所有「完成」發生的時間，供每日統計用。
    public var doneDates: [Date] {
        switch kind {
        case .grid: return stamps.compactMap { (start...end).contains($0.key) ? $0.value : nil }
        case .list: return items.compactMap(\.doneAt)
        case .routine: return []
        }
    }

    public func isDone(_ n: Int) -> Bool { stamps[n] != nil }

    /// 第一個還沒蓋的格子在範圍內的序號（從 0 起）；全蓋完回傳 nil。
    public var firstUndoneIndex: Int? {
        guard kind == .grid, end >= start else { return nil }
        for n in start...end where stamps[n] == nil { return n - start }
        return nil
    }
}

extension TrackGroup: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, kind, start, end, stamps, items, routines, collapsed, deadline, deadlineSetAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        kind = try c.decode(GroupKind.self, forKey: .kind)
        start = try c.decodeIfPresent(Int.self, forKey: .start) ?? 1
        end = try c.decodeIfPresent(Int.self, forKey: .end) ?? 1
        // JSON 的鍵只能是字串，所以存成 {"12": "2026-11-13T…"}
        let raw = try c.decodeIfPresent([String: Date].self, forKey: .stamps) ?? [:]
        var parsed: [Int: Date] = [:]
        for (key, value) in raw {
            if let n = Int(key) { parsed[n] = value }
        }
        stamps = parsed
        items = try c.decodeIfPresent([ListItem].self, forKey: .items) ?? []
        routines = try c.decodeIfPresent([Routine].self, forKey: .routines) ?? []
        collapsed = try c.decodeIfPresent(Bool.self, forKey: .collapsed) ?? false
        deadline = try c.decodeIfPresent(Date.self, forKey: .deadline)
        deadlineSetAt = try c.decodeIfPresent(Date.self, forKey: .deadlineSetAt)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(kind, forKey: .kind)
        try c.encode(start, forKey: .start)
        try c.encode(end, forKey: .end)
        var raw: [String: Date] = [:]
        for (n, date) in stamps { raw[String(n)] = date }
        try c.encode(raw, forKey: .stamps)
        try c.encode(items, forKey: .items)
        try c.encode(routines, forKey: .routines)
        try c.encode(collapsed, forKey: .collapsed)
        try c.encodeIfPresent(deadline, forKey: .deadline)
        try c.encodeIfPresent(deadlineSetAt, forKey: .deadlineSetAt)
    }
}

public struct Project: Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var groups: [TrackGroup]
    public var createdAt: Date
    /// 最近一次蓋章／勾選的時間，首頁按它排序
    public var lastActiveAt: Date
    public var archived: Bool
    /// 最近在做的那個分組，迷你條顯示它
    public var currentGroupID: UUID?
    /// 截止日：那一天結束前做完
    public var deadline: Date?
    public var deadlineSetAt: Date?

    public init(id: UUID = UUID(), name: String, now: Date = Date()) {
        self.id = id
        self.name = name
        self.groups = []
        self.createdAt = now
        self.lastActiveAt = now
        self.archived = false
        self.currentGroupID = nil
        self.deadline = nil
        self.deadlineSetAt = nil
    }

    public var total: Int { groups.reduce(0) { $0 + $1.total } }
    public var doneCount: Int { groups.reduce(0) { $0 + $1.doneCount } }
    public var fraction: Double { total == 0 ? 0 : Double(doneCount) / Double(total) }
    public var isComplete: Bool { total > 0 && doneCount == total }
    public var doneDates: [Date] { groups.flatMap(\.doneDates) }

    /// 迷你條該顯示的分組：最近在做的 → 第一個沒做完的 → 第一個。
    public var currentGroup: TrackGroup? {
        if let id = currentGroupID, let g = groups.first(where: { $0.id == id }) { return g }
        return groups.first(where: { $0.kind != .routine && !$0.isComplete }) ?? groups.first
    }
}

extension Project: Codable {
    enum CodingKeys: String, CodingKey {
        case id, name, groups, createdAt, lastActiveAt, archived, currentGroupID, deadline, deadlineSetAt
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        groups = try c.decodeIfPresent([TrackGroup].self, forKey: .groups) ?? []
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        lastActiveAt = try c.decodeIfPresent(Date.self, forKey: .lastActiveAt) ?? createdAt
        archived = try c.decodeIfPresent(Bool.self, forKey: .archived) ?? false
        currentGroupID = try c.decodeIfPresent(UUID.self, forKey: .currentGroupID)
        deadline = try c.decodeIfPresent(Date.self, forKey: .deadline)
        deadlineSetAt = try c.decodeIfPresent(Date.self, forKey: .deadlineSetAt)
    }
}

/// 提醒方式：該做的事沒做、配速落後時怎麼告訴你。
public enum ReminderMode: String, Codable, Sendable, CaseIterable {
    /// 菜單欄標記，外加每天定時發一條系統通知
    case notification
    /// 只在菜單欄圖標旁加一個小點
    case badge
    /// 不提醒，打開面板才看得到
    case off
}

public struct Settings: Equatable, Sendable {
    /// 一天從幾點開始算（0–6）。熬夜過零點的人可以設成 4。
    public var dayStartHour: Int
    /// 菜單欄固定顯示哪個項目；nil 表示跟著最近操作的走。
    public var menuBarProjectID: UUID?
    public var reminder: ReminderMode
    /// 系統通知每天幾點幾分發
    public var notifyHour: Int
    public var notifyMinute: Int

    public init(dayStartHour: Int = 0, menuBarProjectID: UUID? = nil, reminder: ReminderMode = .badge,
                notifyHour: Int = 21, notifyMinute: Int = 0) {
        self.dayStartHour = dayStartHour
        self.menuBarProjectID = menuBarProjectID
        self.reminder = reminder
        self.notifyHour = notifyHour
        self.notifyMinute = notifyMinute
    }
}

extension Settings: Codable {
    enum CodingKeys: String, CodingKey { case dayStartHour, menuBarProjectID, reminder, notifyHour, notifyMinute }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        dayStartHour = try c.decodeIfPresent(Int.self, forKey: .dayStartHour) ?? 0
        menuBarProjectID = try c.decodeIfPresent(UUID.self, forKey: .menuBarProjectID)
        reminder = (try? c.decodeIfPresent(ReminderMode.self, forKey: .reminder)) ?? .badge
        notifyHour = try c.decodeIfPresent(Int.self, forKey: .notifyHour) ?? 21
        notifyMinute = try c.decodeIfPresent(Int.self, forKey: .notifyMinute) ?? 0
    }
}

public struct AppData: Equatable, Sendable {
    public var version: Int
    public var projects: [Project]
    public var settings: Settings

    public init(version: Int = 1, projects: [Project] = [], settings: Settings = Settings()) {
        self.version = version
        self.projects = projects
        self.settings = settings
    }

    public var activeProjects: [Project] {
        projects.filter { !$0.archived }.sorted { $0.lastActiveAt > $1.lastActiveAt }
    }

    public var archivedProjects: [Project] {
        projects.filter(\.archived).sorted { $0.lastActiveAt > $1.lastActiveAt }
    }

    /// 菜單欄和迷你條預設顯示的項目。
    public var focusProject: Project? {
        if let id = settings.menuBarProjectID,
           let p = projects.first(where: { $0.id == id && !$0.archived }) {
            return p
        }
        // 只有循環任務的項目沒有「已完成／總數」，不讓它把菜單欄的數字搶走
        let active = activeProjects
        return active.first(where: { $0.total > 0 }) ?? active.first
    }
}

extension AppData: Codable {
    enum CodingKeys: String, CodingKey { case version, projects, settings }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
        projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
        settings = try c.decodeIfPresent(Settings.self, forKey: .settings) ?? Settings()
    }
}
