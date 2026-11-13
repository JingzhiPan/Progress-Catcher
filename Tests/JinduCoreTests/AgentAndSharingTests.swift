import Foundation
import Testing
@testable import JinduCore

private func tempDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("jindu-test-\(UUID().uuidString)")
}

private func parse(_ text: String) -> [String: Any] {
    // 修改類工具回傳「一句話 + 換行 + JSON」，讀取類只有 JSON
    let start = text.firstIndex(of: "{") ?? text.startIndex
    return (try? JSONSerialization.jsonObject(with: Data(text[start...].utf8))) as? [String: Any] ?? [:]
}

// MARK: 兩個程式共用同一份資料

@MainActor @Test func twoStoresOnOneFileNeverOverwriteEachOther() {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }

    let app = Store(directory: dir)      // 菜單欄 app
    let agent = Store(directory: dir)    // MCP 服務
    let p = app.addProject(name: "書稿")
    let g = app.addGridGroup(project: p, name: "一", start: 1, end: 10)!

    // agent 手上的資料是舊的（還沒有這個項目），它直接寫也不會把 app 的蓋掉
    let q = agent.addProject(name: "日常")
    #expect(agent.data.projects.map(\.name) == ["書稿", "日常"])

    // app 還沒重讀就接著蓋章：先併入 agent 的修改，再套自己的
    app.setStamp(3, done: true, group: g, project: p)
    #expect(app.data.projects.count == 2)
    #expect(app.project(p)?.doneCount == 1)

    // 交錯著來幾輪
    for n in 4...6 {
        agent.setStamp(n, done: true, group: g, project: p)
        app.addItem("x\(n)", group: app.addListGroup(project: q, name: "清單 \(n)")!, project: q)
    }
    #expect(agent.refresh())
    #expect(app.refresh() == false) // app 剛寫完，手上就是最新的
    #expect(app.data == agent.data)
    #expect(app.project(p)?.doneCount == 4)
    #expect(app.project(q)?.groups.count == 3)

    // 重新開一個也讀到一樣的
    #expect(Store(directory: dir).data == app.data)
}

@MainActor @Test func refreshKeepsOurDataWhenTheFileIsDamagedOrGone() throws {
    let dir = tempDir()
    defer { try? FileManager.default.removeItem(at: dir) }
    let store = Store(directory: dir)
    let p = store.addProject(name: "書稿")
    let file = dir.appendingPathComponent("data.json")

    try Data("壞掉".utf8).write(to: file)
    #expect(store.refresh() == false)
    #expect(store.data.projects.count == 1)
    store.renameProject(p, to: "書稿二") // 下一次修改把好的資料寫回去
    #expect(Store(directory: dir).data.projects.first?.name == "書稿二")

    try FileManager.default.removeItem(at: file)
    store.setArchived(p, true)
    #expect(Store(directory: dir).data.projects.first?.archived == true)
}

// MARK: agent 工具

@MainActor @Test func agentCanLayOutAWholePlan() throws {
    let store = Store(directory: nil)
    let now = Date()
    func call(_ name: String, _ args: [String: Any]) throws -> String {
        try AgentTools.call(name, arguments: args, store: store, now: now)
    }
    let due = AgentTools.dayString(now.addingTimeInterval(9 * 86400))

    _ = try call("create_project", ["name": "書稿", "deadline": due])
    _ = try call("add_grid", ["project": "書稿", "name": "第三章", "start": 77, "end": 124])
    _ = try call("add_grid", ["project": "書稿", "name": "第四章", "start": 125.0, "end": "160", "deadline": due]) // 數字給成小數或字串也收
    _ = try call("add_checklist", ["project": "書稿", "name": "交稿前", "items": ["核對頁碼", "統一術語"]])
    let again = try call("add_checklist", ["project": " 書稿 ", "name": "交稿前", "items": ["統一術語", "寄給編輯"]])
    #expect(again.contains("added 1 item(s), skipped 1"))
    _ = try call("add_routine", ["project": "書稿", "title": "背單字", "frequency": "daily"])
    _ = try call("add_routine", ["project": "書稿", "title": "讀書會", "frequency": "weekdays", "weekdays": ["mon", "Wed"]])
    _ = try call("add_routine", ["project": "書稿", "title": "寫筆記", "frequency": "weekly", "times": 3])
    _ = try call("add_routine", ["project": "書稿", "title": "整理", "frequency": "every_n_days", "interval_days": 3])

    let project = store.data.projects[0]
    #expect(project.groups.map(\.name) == ["第三章", "第四章", "交稿前", "循環任務"])
    #expect(project.groups[1].end == 160)
    #expect(project.groups[1].deadline != nil)
    #expect(project.groups[2].items.map(\.title) == ["核對頁碼", "統一術語", "寄給編輯"])
    #expect(project.groups[3].routines.map(\.rule) == [.daily, .weekdays([2, 4]), .quota(times: 3, per: .week), .everyN(days: 3)])

    // 蓋章、勾清單、記循環任務
    #expect(try call("mark_done", ["project": "書稿", "group": "第三章", "cells": "77-96, 101"]).contains("Stamped 21"))
    #expect(try call("mark_done", ["project": "書稿", "group": "第三章", "cells": "95–97"]).contains("Stamped 1 cell(s) in \"第三章\"; 2 were already"))
    _ = try call("mark_done", ["project": "書稿", "group": "第三章", "cells": "101", "done": false])
    _ = try call("mark_done", ["project": "書稿", "group": "交稿前", "items": ["核對頁碼"]])
    _ = try call("log_routine", ["project": "書稿", "title": "背單字"])
    #expect(try call("log_routine", ["project": "書稿", "title": "背單字"]).contains("already complete"))
    _ = try call("log_routine", ["project": "書稿", "title": "背單字", "undo": true])

    let view = parse(try call("get_overview", [:]))
    let p = (view["projects"] as! [[String: Any]])[0]
    #expect(p["done"] as? Int == 22)
    #expect(p["total"] as? Int == 87)
    #expect((p["deadline"] as? [String: Any])?["days_left_including_today"] as? Int == 10)
    let groups = p["groups"] as! [[String: Any]]
    #expect(groups[0]["done_cells"] as? String == "77-97")
    #expect(groups[0]["kind"] as? String == "grid")
    let routines = groups[3]["routines"] as! [[String: Any]]
    #expect(routines[0]["done"] as? Int == 0)
    #expect(routines[2]["frequency"] as? String == "3x per week")
    #expect(view["today"] as? String == AgentTools.dayString(now))

    // 清掉截止日
    _ = try call("set_deadline", ["project": "書稿", "date": "none"])
    #expect(store.data.projects[0].deadline == nil)
    _ = try call("set_deadline", ["project": "書稿", "group": "第三章", "date": due])
    #expect(store.data.projects[0].groups[0].deadline != nil)
}

@MainActor @Test func agentMistakesAreExplainedAndChangeNothing() throws {
    let store = Store(directory: nil)
    func message(_ name: String, _ args: [String: Any]) -> String {
        do { return "OK: " + (try AgentTools.call(name, arguments: args, store: store)) }
        catch let e as ToolError { return e.message }
        catch { return "\(error)" }
    }
    #expect(message("add_grid", ["project": "沒有", "name": "一", "start": 1, "end": 3]).contains("none yet — use create_project"))
    _ = message("create_project", ["name": "書稿"])
    #expect(message("create_project", ["name": "書稿"]).contains("already exists"))
    #expect(message("create_project", [:]).contains("Missing required argument `name`"))
    #expect(message("create_project", ["name": "乙", "deadline": "下週五"]).contains("Use YYYY-MM-DD"))
    #expect(store.data.projects.count == 1) // 日期不對時項目也沒建

    _ = message("add_grid", ["project": "書稿", "name": "一", "start": 1, "end": 5])
    #expect(message("add_grid", ["project": "書稿", "name": "一", "start": 6, "end": 9]).contains("already has a group"))
    #expect(message("add_grid", ["project": "書稿", "name": "二", "start": 9, "end": 3]).contains("Invalid range"))
    #expect(message("add_grid", ["project": "書稿", "name": "二", "start": 1, "end": 99999]).contains("Split it"))

    // 範圍外的格子：整筆不動
    #expect(message("mark_done", ["project": "書稿", "group": "一", "cells": "4-7"]).contains("outside this grid's range 1–5"))
    #expect(store.data.projects[0].doneCount == 0)
    #expect(message("mark_done", ["project": "書稿", "group": "一", "cells": "第三格"]).contains("Could not read"))
    #expect(message("mark_done", ["project": "書稿", "group": "一"]).contains("pass `cells`"))
    #expect(message("mark_done", ["project": "書稿", "group": "不存在", "cells": "1"]).contains("Groups: 一"))

    #expect(message("add_routine", ["project": "書稿", "title": "x", "frequency": "weekdays"]).contains("needs `weekdays`"))
    #expect(message("add_routine", ["project": "書稿", "title": "x", "frequency": "weekly", "times": 9]).contains("1–7"))
    #expect(message("add_routine", ["project": "書稿", "title": "x", "frequency": "every_n_days", "interval_days": 1]).contains("between 2 and 365"))
    #expect(message("add_routine", ["project": "書稿", "title": "x", "frequency": "hourly"]).contains("Unknown frequency"))
    #expect(store.data.projects[0].groups.count == 1) // 失敗的 add_routine 沒留下空分組
    #expect(message("log_routine", ["project": "書稿", "title": "x"]).contains("No routine titled"))
    #expect(message("nope", [:]).contains("Unknown tool"))
}

/// 參數照真實情況走一遍：agent 送來的是 JSON 文字，解出來的數字是 NSNumber，不是 Swift 的 Int。
/// 0.3.0 就是栽在這裡——測試都用 Swift 字面值，沒發現「1」過不了。
@MainActor @Test func argumentsArrivingAsRealJSONAreReadCorrectly() throws {
    let store = Store(directory: nil)
    func call(_ name: String, _ argumentsJSON: String) -> String {
        let args = (try? JSONSerialization.jsonObject(with: Data(argumentsJSON.utf8))) as? [String: Any] ?? [:]
        do { return "OK: " + (try AgentTools.call(name, arguments: args, store: store)) }
        catch let e as ToolError { return e.message }
        catch { return "\(error)" }
    }
    _ = call("create_project", #"{"name": "示例書稿"}"#)
    // 使用者實際碰到的那兩筆：從 1 開始
    #expect(call("add_grid", #"{"project": "示例書稿", "name": "第五章", "start": 1, "end": 62}"#).hasPrefix("OK"))
    #expect(call("add_grid", #"{"project": "示例書稿", "name": "第七章", "start": 1, "end": 60}"#).hasPrefix("OK"))
    #expect(call("add_grid", #"{"project": "示例書稿", "name": "序", "start": 0, "end": 1}"#).hasPrefix("OK"))
    #expect(call("add_grid", #"{"project": "示例書稿", "name": "附錄", "start": 1.0, "end": "3"}"#).hasPrefix("OK"))
    #expect(store.data.projects[0].groups.map(\.total) == [62, 60, 2, 3])

    // 次數、間隔是 1 也要收
    #expect(call("add_routine", #"{"project": "示例書稿", "title": "週會", "frequency": "weekly", "times": 1}"#).hasPrefix("OK"))
    #expect(call("add_routine", #"{"project": "示例書稿", "title": "月結", "frequency": "monthly", "times": 1}"#).hasPrefix("OK"))

    // 真的布林不能冒充數字，小數也不行
    #expect(call("add_grid", #"{"project": "示例書稿", "name": "壞一", "start": true, "end": 5}"#).contains("non-integer argument `start`"))
    #expect(call("add_grid", #"{"project": "示例書稿", "name": "壞二", "start": 1, "end": 5.5}"#).contains("non-integer argument `end`"))

    // 布林參數照常：done=false 是取消，undo=true 是撤銷
    _ = call("mark_done", #"{"project": "示例書稿", "group": "第五章", "cells": "1-3"}"#)
    #expect(call("mark_done", #"{"project": "示例書稿", "group": "第五章", "cells": "1", "done": false}"#).contains("Cleared 1"))
    #expect(store.data.projects[0].groups[0].doneCount == 2)
    _ = call("log_routine", #"{"project": "示例書稿", "title": "週會"}"#)
    #expect(call("log_routine", #"{"project": "示例書稿", "title": "週會", "undo": true}"#).contains("Removed the latest record"))
}

@MainActor @Test func everyToolIsDefinedWithASchema() {
    let names = AgentTools.definitions.compactMap { $0["name"] as? String }
    #expect(names == ["get_overview", "create_project", "add_grid", "add_checklist", "add_routine", "set_deadline", "mark_done", "log_routine"])
    for tool in AgentTools.definitions {
        let schema = tool["inputSchema"] as? [String: Any]
        let properties = schema?["properties"] as? [String: Any] ?? [:]
        for key in schema?["required"] as? [String] ?? [] { #expect(properties[key] != nil) }
        #expect(JSONSerialization.isValidJSONObject(tool))
        #expect((tool["description"] as? String ?? "").count > 40)
    }
    #expect(AgentTools.compress([5, 1, 2, 3, 9, 8]) == "1-3,5,8-9")
}
