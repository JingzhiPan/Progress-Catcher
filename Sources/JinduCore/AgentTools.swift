import Foundation

/// 工具呼叫出錯時回給 agent 看的訊息（英文，因為讀的是模型）。
public struct ToolError: Error, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
}

/// 給 agent 用的那組工具：定義（名字、說明、參數）和實作都在這裡，跟傳輸方式無關。
/// MCP 服務只負責把 JSON-RPC 轉進來。項目、分組、循環任務一律用「名字」指認，agent 不用記 ID。
///
/// 故意沒有刪除類的工具：agent 排錯了可以再加、可以歸檔，但刪記錄這件事留給人在面板裡做。
@MainActor
public enum AgentTools {
    public static let serverInstructions = """
    Progress Catcher is the user's menu bar progress tracker. Data is organised as project → group. \
    A group is one of: a numbered grid (cells start…end, stamped one by one — pages, episodes, exercises), \
    a checklist of named items, or a set of routines that recur on a schedule. \
    Call get_overview first to see what exists; projects, groups and routines are addressed by their names. \
    Deadlines can sit on a project or on a grid/checklist group, and the app then shows the daily pace needed. \
    Changes appear in the user's panel immediately. There are no delete tools; ask the user to remove things in the app.
    """

    // MARK: 定義

    public static var definitions: [[String: Any]] {
        [
            tool("get_overview", title: "Read progress",
                 "Read everything the tracker holds: each project with its groups, progress counts, which grid cells are done, " +
                 "checklist items, routines and whether they are due today, deadlines and required daily pace. " +
                 "Pass `project` to limit the output to one project.",
                 properties: ["project": str("Optional project name to show only that project.")],
                 required: [], readOnly: true),

            tool("create_project", title: "Create a project",
                 "Create a new, empty project. Add groups to it afterwards with add_grid, add_checklist or add_routine. " +
                 "Fails if an active project with the same name already exists.",
                 properties: [
                    "name": str("Project name, in the user's language."),
                    "deadline": str("Optional due date for the whole project, YYYY-MM-DD."),
                 ],
                 required: ["name"]),

            tool("add_grid", title: "Add a numbered grid",
                 "Add a group of numbered cells to a project, one cell per unit of work (page 77 to 124, episode 1 to 12…). " +
                 "The user stamps cells as they finish them. Split long work into several grids (e.g. one per chapter) so each can have its own deadline.",
                 properties: [
                    "project": str("Name of an existing project."),
                    "name": str("Group name, e.g. the chapter title."),
                    "start": int("First number, inclusive (0 or greater)."),
                    "end": int("Last number, inclusive. At most \(Store.maxGridCells) cells per grid."),
                    "deadline": str("Optional due date for this grid, YYYY-MM-DD."),
                 ],
                 required: ["project", "name", "start", "end"]),

            tool("add_checklist", title: "Add a checklist or items",
                 "Add a checklist of named items to a project. If a checklist with this name already exists, the items are appended to it " +
                 "(items whose title is already there are skipped).",
                 properties: [
                    "project": str("Name of an existing project."),
                    "name": str("Checklist name."),
                    "items": ["type": "array", "items": ["type": "string"], "description": "Item titles, in order."],
                    "deadline": str("Optional due date for this checklist, YYYY-MM-DD."),
                 ],
                 required: ["project", "name"]),

            tool("add_routine", title: "Add a recurring task",
                 "Add a task that recurs on a schedule. frequency is one of: " +
                 "\"daily\"; \"weekdays\" (needs `weekdays`, the fixed days it falls on); " +
                 "\"weekly\" or \"monthly\" (needs `times`: do it that many times within the week/month, on any days); " +
                 "\"every_n_days\" (needs `interval_days`, counted from today). " +
                 "A missed occurrence does not carry over to the next day.",
                 properties: [
                    "project": str("Name of an existing project."),
                    "title": str("What to do, e.g. \"Review vocabulary\". Must be unique within the project."),
                    "frequency": ["type": "string", "enum": ["daily", "weekdays", "weekly", "monthly", "every_n_days"]],
                    "weekdays": ["type": "array", "items": ["type": "string", "enum": ["mon", "tue", "wed", "thu", "fri", "sat", "sun"]],
                                 "description": "For frequency \"weekdays\"."],
                    "times": int("For \"weekly\" (1–7) or \"monthly\" (1–31): how many times per period."),
                    "interval_days": int("For \"every_n_days\": 2–365."),
                    "group": str("Optional name of the routine group to put it in; created if missing. Defaults to the project's first routine group."),
                 ],
                 required: ["project", "title", "frequency"]),

            tool("set_deadline", title: "Set or clear a deadline",
                 "Set the due date of a project, or of one grid/checklist group inside it. The app then shows how much is left and the daily pace needed, " +
                 "and flags it when progress falls behind an even pace. Pass date \"none\" to remove the deadline.",
                 properties: [
                    "project": str("Name of an existing project."),
                    "group": str("Optional group name. Omit to set the deadline on the project itself."),
                    "date": str("YYYY-MM-DD, or \"none\" to clear."),
                 ],
                 required: ["project", "date"]),

            tool("mark_done", title: "Mark cells or items done",
                 "Stamp grid cells or tick checklist items as done (or undo with done=false). Only use this when the user says the work was actually done; " +
                 "it records today's date for each one and feeds their daily statistics.",
                 properties: [
                    "project": str("Name of an existing project."),
                    "group": str("Name of the grid or checklist."),
                    "cells": str("For a grid: numbers and ranges, e.g. \"77-96, 101\"."),
                    "items": ["type": "array", "items": ["type": "string"], "description": "For a checklist: titles of the items."],
                    "done": ["type": "boolean", "description": "Defaults to true. false removes the mark."],
                 ],
                 required: ["project", "group"]),

            tool("log_routine", title: "Log a recurring task",
                 "Record that a recurring task was done today (or undo the latest record with undo=true). " +
                 "Only works when the task is scheduled for today; otherwise it reports when it is next due.",
                 properties: [
                    "project": str("Name of an existing project."),
                    "title": str("Title of the routine."),
                    "undo": ["type": "boolean", "description": "true removes the most recent record of today / this period."],
                 ],
                 required: ["project", "title"]),
        ]
    }

    // MARK: 呼叫

    public static func call(_ name: String, arguments args: [String: Any], store: Store, now: Date = Date()) throws -> String {
        store.refresh()
        switch name {
        case "get_overview":
            if let ref = optionalString(args, "project") {
                let project = try findProject(ref, store)
                return json(["today": dayString(now), "projects": [describe(project, store, now)]])
            }
            return json(overview(store, now))

        case "create_project":
            let name = try requiredString(args, "name")
            if store.data.projects.contains(where: { !$0.archived && same($0.name, name) }) {
                throw ToolError("A project named \"\(name)\" already exists. Add to it, or choose another name.")
            }
            let deadline = try optionalDate(args, "deadline")
            let id = store.addProject(name: name, now: now)
            if let deadline { store.setDeadline(deadline, project: id, now: now) }
            return try done("Created project \"\(name)\".", id, store, now)

        case "add_grid":
            let project = try findProject(try requiredString(args, "project"), store)
            let name = try requiredString(args, "name")
            let start = try requiredInt(args, "start"), end = try requiredInt(args, "end")
            try ensureNoGroup(named: name, in: project)
            guard Store.isValidRange(start: start, end: end) else {
                throw ToolError("Invalid range \(start)–\(end): start must be ≥ 0, end ≥ start, and at most \(Store.maxGridCells) cells. Split it into several grids.")
            }
            let deadline = try optionalDate(args, "deadline")
            guard let gid = store.addGridGroup(project: project.id, name: name, start: start, end: end) else {
                throw ToolError("Could not add the grid.")
            }
            if let deadline { store.setDeadline(deadline, group: gid, project: project.id, now: now) }
            return try done("Added grid \"\(name)\" (\(start)–\(end), \(end - start + 1) cells).", project.id, store, now)

        case "add_checklist":
            let project = try findProject(try requiredString(args, "project"), store)
            let name = try requiredString(args, "name")
            let titles = stringArray(args, "items")
            let deadline = try optionalDate(args, "deadline")
            let gid: UUID
            var note = ""
            if let existing = project.groups.first(where: { same($0.name, name) }) {
                guard existing.kind == .list else {
                    throw ToolError("\"\(name)\" already exists in this project and is not a checklist.")
                }
                gid = existing.id
                note = "Checklist \"\(name)\" already existed; "
            } else {
                guard let created = store.addListGroup(project: project.id, name: name) else { throw ToolError("Could not add the checklist.") }
                gid = created
                note = "Created checklist \"\(name)\"; "
            }
            let have = store.project(project.id)?.groups.first { $0.id == gid }?.items.map(\.title) ?? []
            var added = 0, skipped = 0
            var seen = have
            for title in titles {
                if seen.contains(where: { same($0, title) }) {
                    skipped += 1
                } else if store.addItem(title, group: gid, project: project.id) != nil {
                    added += 1
                    seen.append(title)
                }
            }
            if let deadline { store.setDeadline(deadline, group: gid, project: project.id, now: now) }
            return try done(note + "added \(added) item(s)" + (skipped > 0 ? ", skipped \(skipped) already present." : "."), project.id, store, now)

        case "add_routine":
            let project = try findProject(try requiredString(args, "project"), store)
            let title = try requiredString(args, "title")
            let rule = try parseRule(args)
            if project.groups.flatMap(\.routines).contains(where: { same($0.title, title) }) {
                throw ToolError("A routine titled \"\(title)\" already exists in this project.")
            }
            let gid: UUID
            if let groupName = optionalString(args, "group") {
                if let existing = project.groups.first(where: { same($0.name, groupName) }) {
                    guard existing.kind == .routine else { throw ToolError("\"\(groupName)\" exists but is not a routine group.") }
                    gid = existing.id
                } else {
                    guard let created = store.addRoutineGroup(project: project.id, name: groupName) else { throw ToolError("Could not add the group.") }
                    gid = created
                }
            } else if let existing = project.groups.first(where: { $0.kind == .routine }) {
                gid = existing.id
            } else {
                guard let created = store.addRoutineGroup(project: project.id, name: "") else { throw ToolError("Could not add the group.") }
                gid = created
            }
            guard store.addRoutine(title, rule: rule, group: gid, project: project.id, now: now) != nil else {
                throw ToolError("Could not add the routine.")
            }
            return try done("Added routine \"\(title)\" (\(frequencyText(rule))).", project.id, store, now)

        case "set_deadline":
            let project = try findProject(try requiredString(args, "project"), store)
            let raw = try requiredString(args, "date")
            let clear = ["none", "null", "clear"].contains(raw.lowercased())
            let date = clear ? nil : try parseDate(raw)
            if let groupName = optionalString(args, "group") {
                let group = try findGroup(groupName, in: project)
                guard group.kind != .routine else { throw ToolError("Routine groups have no deadline.") }
                store.setDeadline(date, group: group.id, project: project.id, now: now)
                return try done(clear ? "Cleared the deadline of \"\(group.name)\"." : "Deadline of \"\(group.name)\" set to \(raw).", project.id, store, now)
            }
            store.setDeadline(date, project: project.id, now: now)
            return try done(clear ? "Cleared the project deadline." : "Project deadline set to \(raw).", project.id, store, now)

        case "mark_done":
            let project = try findProject(try requiredString(args, "project"), store)
            let group = try findGroup(try requiredString(args, "group"), in: project)
            let isDone = (args["done"] as? Bool) ?? true
            switch group.kind {
            case .grid:
                guard let spec = optionalString(args, "cells") else {
                    throw ToolError("\"\(group.name)\" is a grid (\(group.start)–\(group.end)); pass `cells`, e.g. \"\(group.start)-\(min(group.end, group.start + 4))\".")
                }
                let numbers = try parseCells(spec)
                let outside = numbers.filter { !(group.start...group.end).contains($0) }
                guard outside.isEmpty else {
                    throw ToolError("Cells \(compress(outside)) are outside this grid's range \(group.start)–\(group.end). Nothing was changed.")
                }
                let changing = numbers.filter { group.isDone($0) != isDone }
                for n in changing { store.setStamp(n, done: isDone, group: group.id, project: project.id, now: now) }
                return try done("\(isDone ? "Stamped" : "Cleared") \(changing.count) cell(s) in \"\(group.name)\"" +
                                (changing.count < numbers.count ? "; \(numbers.count - changing.count) were already that way." : "."),
                                project.id, store, now)
            case .list:
                let titles = stringArray(args, "items")
                guard !titles.isEmpty else { throw ToolError("\"\(group.name)\" is a checklist; pass `items` with the titles to mark.") }
                var targets: [ListItem] = []
                for title in titles {
                    guard let item = group.items.first(where: { same($0.title, title) }) else {
                        throw ToolError("No item titled \"\(title)\" in \"\(group.name)\". Items: \(group.items.map(\.title).joined(separator: " | ")). Nothing was changed.")
                    }
                    targets.append(item)
                }
                for item in targets { store.setItemDone(item.id, done: isDone, group: group.id, project: project.id, now: now) }
                return try done("\(isDone ? "Ticked" : "Unticked") \(targets.count) item(s) in \"\(group.name)\".", project.id, store, now)
            case .routine:
                throw ToolError("\"\(group.name)\" is a routine group; use log_routine instead.")
            }

        case "log_routine":
            let project = try findProject(try requiredString(args, "project"), store)
            let title = try requiredString(args, "title")
            guard let (group, routine) = project.groups.lazy
                .flatMap({ g in g.routines.map { (g, $0) } })
                .first(where: { same($0.1.title, title) }) else {
                let all = project.groups.flatMap(\.routines).map(\.title)
                throw ToolError("No routine titled \"\(title)\" in \"\(project.name)\". Routines: \(all.isEmpty ? "(none)" : all.joined(separator: " | ")).")
            }
            let state = routine.state(now: now, clock: store.clock)
            if (args["undo"] as? Bool) == true {
                guard state.done > 0 else { throw ToolError("Nothing to undo: \"\(routine.title)\" has no record for today / this period.") }
                store.undoRoutine(routine.id, group: group.id, project: project.id, now: now)
                return try done("Removed the latest record of \"\(routine.title)\".", project.id, store, now)
            }
            guard state.isDueToday else {
                let next = state.nextDue.map { " Next due \(dayString($0))." } ?? ""
                throw ToolError("\"\(routine.title)\" is not scheduled for today.\(next)")
            }
            guard !state.isSatisfied else {
                return try done("\"\(routine.title)\" was already complete (\(state.done)/\(state.target)); nothing changed.", project.id, store, now)
            }
            store.tapRoutine(routine.id, group: group.id, project: project.id, now: now)
            return try done("Logged \"\(routine.title)\".", project.id, store, now)

        default:
            throw ToolError("Unknown tool \"\(name)\".")
        }
    }

    // MARK: 描述現況

    static func overview(_ store: Store, _ now: Date) -> [String: Any] {
        let clock = store.clock
        var out: [String: Any] = [
            "today": dayString(now),
            "projects": store.data.activeProjects.map { describe($0, store, now) },
            "needs_attention": store.data.attentionCount(now: now, clock: clock),
        ]
        let archived = store.data.archivedProjects.map(\.name)
        if !archived.isEmpty { out["archived_projects"] = archived }
        return out
    }

    static func describe(_ project: Project, _ store: Store, _ now: Date) -> [String: Any] {
        let clock = store.clock
        var out: [String: Any] = ["name": project.name]
        if project.archived { out["archived"] = true }
        if project.total > 0 {
            out["done"] = project.doneCount
            out["total"] = project.total
            out["done_today"] = clock.count(of: project.doneDates, onDayOf: now)
        }
        if let deadline = project.deadline, let pace = project.pace(now: now, clock: clock) {
            out["deadline"] = describe(pace, deadline)
        }
        out["groups"] = project.groups.map { group -> [String: Any] in
            var g: [String: Any] = ["name": group.name]
            switch group.kind {
            case .grid:
                g["kind"] = "grid"
                g["range"] = "\(group.start)-\(group.end)"
                g["done"] = group.doneCount
                g["total"] = group.total
                let stamped = group.stamps.keys.filter { (group.start...group.end).contains($0) }
                if !stamped.isEmpty { g["done_cells"] = compress(stamped) }
            case .list:
                g["kind"] = "checklist"
                g["done"] = group.doneCount
                g["total"] = group.total
                g["items"] = group.items.map { ["title": $0.title, "done": $0.doneAt != nil] as [String: Any] }
            case .routine:
                g["kind"] = "routines"
                g["routines"] = group.routines.map { routine -> [String: Any] in
                    let state = routine.state(now: now, clock: clock)
                    var r: [String: Any] = [
                        "title": routine.title,
                        "frequency": frequencyText(routine.rule),
                        "due_today": state.isDueToday,
                        "done": state.done,
                        "target": state.target,
                    ]
                    if state.streak > 0 { r["streak"] = state.streak }
                    if let next = state.nextDue { r["next_due"] = dayString(next) }
                    return r
                }
            }
            if let deadline = group.deadline, let pace = group.pace(now: now, clock: clock) {
                g["deadline"] = describe(pace, deadline)
            }
            return g
        }
        return out
    }

    static func describe(_ pace: Pace, _ deadline: Date) -> [String: Any] {
        var out: [String: Any] = ["date": dayString(deadline), "remaining": pace.remaining]
        switch pace.status {
        case .complete: out["status"] = "complete"
        case .overdue:
            out["status"] = "overdue"
            out["days_overdue"] = 1 - pace.daysLeft
        case .behind, .onTrack:
            out["status"] = pace.status == .behind ? "behind" : "on_track"
            out["days_left_including_today"] = pace.daysLeft
            out["needed_per_day"] = pace.perDay
            out["done_today"] = pace.doneToday
            if pace.lag > 0 { out["behind_by"] = pace.lag }
        }
        return out
    }

    public static func frequencyText(_ rule: RoutineRule) -> String {
        switch rule {
        case .daily: return "daily"
        case .weekdays(let days):
            let names = [1: "sun", 2: "mon", 3: "tue", 4: "wed", 5: "thu", 6: "fri", 7: "sat"]
            return "weekdays: " + [2, 3, 4, 5, 6, 7, 1].filter(days.contains).compactMap { names[$0] }.joined(separator: ",")
        case .quota(let times, let per): return "\(times)x per \(per == .week ? "week" : "month")"
        case .everyN(let days): return "every \(days) days"
        }
    }

    /// [77, 78, 79, 101] → "77-79,101"
    public static func compress(_ numbers: [Int]) -> String {
        let sorted = Array(Set(numbers)).sorted()
        var parts: [String] = []
        var i = 0
        while i < sorted.count {
            var j = i
            while j + 1 < sorted.count, sorted[j + 1] == sorted[j] + 1 { j += 1 }
            parts.append(i == j ? "\(sorted[i])" : "\(sorted[i])-\(sorted[j])")
            i = j + 1
        }
        return parts.joined(separator: ",")
    }

    // MARK: 解析參數

    /// "77-96, 101" → [77…96, 101]
    public static func parseCells(_ spec: String) throws -> [Int] {
        var out: [Int] = []
        let cleaned = spec.replacingOccurrences(of: "–", with: "-").replacingOccurrences(of: "，", with: ",").replacingOccurrences(of: "、", with: ",")
        for part in cleaned.split(whereSeparator: { $0 == "," || $0 == " " || $0 == ";" }) {
            let bounds = part.split(separator: "-", omittingEmptySubsequences: true).map { Int($0) }
            if bounds.count == 1, let n = bounds[0] {
                out.append(n)
            } else if bounds.count == 2, let a = bounds[0], let b = bounds[1], a <= b, b - a < Store.maxGridCells {
                out.append(contentsOf: a...b)
            } else {
                throw ToolError("Could not read \"\(part)\" in cells. Use numbers and ranges like \"77-96, 101\".")
            }
        }
        guard !out.isEmpty else { throw ToolError("`cells` is empty. Use numbers and ranges like \"77-96, 101\".") }
        return Array(Set(out)).sorted()
    }

    static func parseRule(_ args: [String: Any]) throws -> RoutineRule {
        let frequency = try requiredString(args, "frequency").lowercased()
        let rule: RoutineRule
        switch frequency {
        case "daily":
            rule = .daily
        case "weekdays":
            let map = ["sun": 1, "mon": 2, "tue": 3, "wed": 4, "thu": 5, "fri": 6, "sat": 7]
            let names = stringArray(args, "weekdays")
            let days = names.compactMap { map[String($0.lowercased().prefix(3))] }
            guard !days.isEmpty, days.count == names.count else {
                throw ToolError("frequency \"weekdays\" needs `weekdays`, e.g. [\"mon\", \"wed\", \"fri\"].")
            }
            rule = .weekdays(Array(Set(days)).sorted())
        case "weekly", "monthly":
            guard let times = intValue(args["times"]) else { throw ToolError("frequency \"\(frequency)\" needs `times`.") }
            guard times >= 1, times <= (frequency == "weekly" ? 7 : 31) else {
                throw ToolError("`times` must be 1–\(frequency == "weekly" ? 7 : 31) for \(frequency).")
            }
            rule = .quota(times: times, per: frequency == "weekly" ? .week : .month)
        case "every_n_days":
            guard let n = intValue(args["interval_days"]), (2...365).contains(n) else {
                throw ToolError("frequency \"every_n_days\" needs `interval_days` between 2 and 365 (use \"daily\" for every day).")
            }
            rule = .everyN(days: n)
        default:
            throw ToolError("Unknown frequency \"\(frequency)\". Use daily, weekdays, weekly, monthly or every_n_days.")
        }
        return rule
    }

    static func parseDate(_ raw: String) throws -> Date {
        let parts = raw.trimmingCharacters(in: .whitespaces).split(separator: "-").map { Int($0) }
        guard parts.count == 3, let y = parts[0], let m = parts[1], let d = parts[2],
              let date = Calendar.current.date(from: DateComponents(year: y, month: m, day: d)),
              Calendar.current.component(.month, from: date) == m else {
            throw ToolError("Could not read the date \"\(raw)\". Use YYYY-MM-DD.")
        }
        return Calendar.current.startOfDay(for: date)
    }

    static func dayString(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: 尋找

    static func findProject(_ ref: String, _ store: Store) throws -> Project {
        let all = store.data.projects
        if let id = UUID(uuidString: ref), let p = all.first(where: { $0.id == id }) { return p }
        let active = all.filter { !$0.archived && same($0.name, ref) }
        if active.count == 1 { return active[0] }
        if active.count > 1 { throw ToolError("More than one project is named \"\(ref)\". Ask the user to rename one in the app.") }
        if let archived = all.first(where: { $0.archived && same($0.name, ref) }) { return archived }
        let names = store.data.activeProjects.map(\.name)
        throw ToolError("No project named \"\(ref)\". Projects: \(names.isEmpty ? "(none yet — use create_project)" : names.joined(separator: " | ")).")
    }

    static func findGroup(_ ref: String, in project: Project) throws -> TrackGroup {
        let matches = project.groups.filter { same($0.name, ref) }
        if matches.count == 1 { return matches[0] }
        if matches.count > 1 { throw ToolError("More than one group in \"\(project.name)\" is named \"\(ref)\". Ask the user to rename one in the app.") }
        let names = project.groups.map(\.name)
        throw ToolError("No group named \"\(ref)\" in \"\(project.name)\". Groups: \(names.isEmpty ? "(none yet)" : names.joined(separator: " | ")).")
    }

    static func ensureNoGroup(named name: String, in project: Project) throws {
        if project.groups.contains(where: { same($0.name, name) }) {
            throw ToolError("\"\(project.name)\" already has a group named \"\(name)\". Choose another name.")
        }
    }

    // MARK: 小工具

    private static func same(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(b.trimmingCharacters(in: .whitespacesAndNewlines)) == .orderedSame
    }

    private static func done(_ message: String, _ projectID: UUID, _ store: Store, _ now: Date) throws -> String {
        guard let project = store.project(projectID) else { return message }
        return message + "\n" + json(["project": describe(project, store, now)])
    }

    static func json(_ object: Any) -> String {
        let options: JSONSerialization.WritingOptions = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: options) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    private static func requiredString(_ args: [String: Any], _ key: String) throws -> String {
        guard let value = optionalString(args, key) else { throw ToolError("Missing required argument `\(key)`.") }
        return value
    }

    private static func optionalString(_ args: [String: Any], _ key: String) -> String? {
        guard let value = args[key] as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func requiredInt(_ args: [String: Any], _ key: String) throws -> Int {
        guard let value = intValue(args[key]) else { throw ToolError("Missing or non-integer argument `\(key)`.") }
        return value
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let s = any as? String { return Int(s.trimmingCharacters(in: .whitespaces)) }
        guard let number = any as? NSNumber else { return nil }
        // JSON 解出來的數字和布林都是 NSNumber。不能用 `is Bool` 分辨：
        // Swift 會把數值剛好是 0 或 1 的 NSNumber 也當成 Bool，於是「start: 1」被當成 true 而拒收
        // （0.3.0 的 bug：從 1 開始的格子一律加不進去）。要看它底層是不是真的布林型別。
        if CFGetTypeID(number) == CFBooleanGetTypeID() { return nil }
        let value = number.doubleValue
        guard value == value.rounded(), abs(value) < 1e15 else { return nil }
        return Int(value)
    }

    private static func optionalDate(_ args: [String: Any], _ key: String) throws -> Date? {
        guard let raw = optionalString(args, key) else { return nil }
        return try parseDate(raw)
    }

    private static func stringArray(_ args: [String: Any], _ key: String) -> [String] {
        ((args[key] as? [Any]) ?? []).compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private static func tool(_ name: String, title: String, _ description: String, properties: [String: Any],
                             required: [String], readOnly: Bool = false) -> [String: Any] {
        [
            "name": name,
            "title": title,
            "description": description,
            "inputSchema": ["type": "object", "properties": properties, "required": required, "additionalProperties": false] as [String: Any],
            "annotations": [
                "title": title,
                "readOnlyHint": readOnly,
                "destructiveHint": false,
                "openWorldHint": false,
            ] as [String: Any],
        ]
    }

    private static func str(_ description: String) -> [String: Any] { ["type": "string", "description": description] }
    private static func int(_ description: String) -> [String: Any] { ["type": "integer", "description": description] }
}
