import Foundation
import Testing
@testable import JinduCore

private func utc() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}

private func date(_ s: String) -> Date {
    ISO8601DateFormatter().date(from: s)!
}

@Test func dayStartsAtMidnightByDefault() {
    let clock = DayClock(startHour: 0, calendar: utc())
    #expect(clock.isSameDay(date("2026-11-13T00:10:00Z"), date("2026-11-13T23:50:00Z")))
    #expect(!clock.isSameDay(date("2026-11-12T23:50:00Z"), date("2026-11-13T00:10:00Z")))
}

@Test func lateNightCountsAsPreviousDayWhenDayStartsAtFour() {
    let clock = DayClock(startHour: 4, calendar: utc())
    // 凌晨 2 點還算前一天
    #expect(clock.isSameDay(date("2026-11-12T22:00:00Z"), date("2026-11-13T02:00:00Z")))
    #expect(!clock.isSameDay(date("2026-11-13T02:00:00Z"), date("2026-11-13T05:00:00Z")))
    #expect(clock.daysBetween(date("2026-11-11T12:00:00Z"), date("2026-11-13T02:00:00Z")) == 1)
}

@Test func historyBucketsByDayOldestFirst() {
    let clock = DayClock(startHour: 0, calendar: utc())
    let now = date("2026-11-13T12:00:00Z")
    let dates = [
        date("2026-11-13T08:00:00Z"), date("2026-11-13T09:00:00Z"),
        date("2026-11-11T20:00:00Z"),
        date("2026-10-01T20:00:00Z"), // 超出視窗，不算
    ]
    let h = clock.history(of: dates, days: 3, now: now)
    #expect(h.map(\.count) == [1, 0, 2])
    #expect(h.last?.day == date("2026-11-13T00:00:00Z"))
    #expect(clock.count(of: dates, onDayOf: now) == 2)
}

@Test func gridMetricsFillsWidthAndMapsPointsBack() {
    let m = GridMetrics(width: 340, count: 23, minCell: 32, gap: 4)
    #expect(m.cols == 9)
    #expect(abs(CGFloat(m.cols) * m.cell + CGFloat(m.cols - 1) * m.gap - 340) < 0.001)
    #expect(m.rows == 3)
    #expect(Array(m.indices(inRow: 2)) == [18, 19, 20, 21, 22])
    for i in 0..<23 { #expect(m.index(at: m.center(of: i)) == i) }
    // 最後一排沒有的格子、格子之間的縫、範圍外
    #expect(m.index(at: m.center(of: 26)) == nil)
    #expect(m.index(at: CGPoint(x: m.cell + 2, y: 5)) == nil)
    #expect(m.index(at: CGPoint(x: -1, y: 5)) == nil)
}

@MainActor @Test func stampingUpdatesCountsAndActivity() {
    let store = Store(directory: nil)
    let early = date("2026-11-01T10:00:00Z")
    let a = store.addProject(name: "甲", now: early)
    let b = store.addProject(name: "乙", now: early.addingTimeInterval(60))
    let g = store.addGridGroup(project: a, name: "", start: 10, end: 19)!
    #expect(store.project(a)?.groups.first?.name == "第 1 組")
    #expect(store.data.focusProject?.id == b)

    let now = date("2026-11-13T10:00:00Z")
    store.setStamp(12, done: true, group: g, project: a, now: now)
    store.setStamp(13, done: true, group: g, project: a, now: now)
    store.setStamp(99, done: true, group: g, project: a, now: now) // 範圍外，忽略
    #expect(store.project(a)?.doneCount == 2)
    #expect(store.project(a)?.total == 10)
    #expect(store.data.focusProject?.id == a) // 剛操作過的排最前
    #expect(store.project(a)?.currentGroup?.id == g)

    store.setStamp(12, done: false, group: g, project: a, now: now)
    #expect(store.project(a)?.groups.first?.stamps.keys.sorted() == [13])

    // 範圍改小：範圍外的章不計數，改回來還在
    #expect(store.setRange(g, project: a, start: 10, end: 12))
    #expect(store.project(a)?.doneCount == 0)
    #expect(store.setRange(g, project: a, start: 10, end: 19))
    #expect(store.project(a)?.doneCount == 1)
    #expect(!store.setRange(g, project: a, start: 5, end: 1))

    store.setMenuBarProject(b)
    #expect(store.data.focusProject?.id == b)
    store.setArchived(b, true)
    #expect(store.data.focusProject?.id == a) // 歸檔的不佔菜單欄
}

@MainActor @Test func listItemsAndReordering() {
    let store = Store(directory: nil)
    let p = store.addProject(name: "甲")
    let g = store.addListGroup(project: p, name: "交稿")!
    let i1 = store.addItem("第一章", group: g, project: p)!
    let i2 = store.addItem("第二章", group: g, project: p)!
    let i3 = store.addItem("第三章", group: g, project: p)!
    #expect(store.addItem("   ", group: g, project: p) == nil)

    store.setItemDone(i2, done: true, group: g, project: p)
    #expect(store.project(p)?.doneCount == 1)
    #expect(store.project(p)?.total == 3)

    store.moveItem(i3, onto: i1, group: g, project: p)
    #expect(store.project(p)?.groups[0].items.map(\.id) == [i3, i1, i2])
    store.moveItem(i3, onto: i2, group: g, project: p)
    #expect(store.project(p)?.groups[0].items.map(\.id) == [i1, i2, i3])

    let g2 = store.addGridGroup(project: p, name: "頁", start: 1, end: 5)!
    store.moveGroup(g2, onto: g, project: p)
    #expect(store.project(p)?.groups.map(\.id) == [g2, g])

    store.deleteItem(i1, group: g, project: p)
    #expect(store.project(p)?.total == 7)
}

@MainActor @Test func dataSurvivesSaveAndReload() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jindu-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = Store(directory: dir)
    let p = store.addProject(name: "譯稿", now: date("2026-11-01T10:00:00Z"))
    let g = store.addGridGroup(project: p, name: "第三章", start: 77, end: 110)!
    store.setStamp(77, done: true, group: g, project: p, now: date("2026-11-13T10:00:00Z"))
    let l = store.addListGroup(project: p, name: "雜項")!
    let item = store.addItem("核對引文", group: l, project: p)!
    store.setItemDone(item, done: true, group: l, project: p, now: date("2026-11-13T11:00:00Z"))
    store.setDayStartHour(4)
    store.flush()

    let reloaded = Store(directory: dir)
    #expect(reloaded.data == store.data)
    #expect(reloaded.project(p)?.groups[0].stamps[77] == date("2026-11-13T10:00:00Z"))
    // 第二次啟動時留了當天的備份
    let backups = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("backups").path)
    #expect(backups.count == 1)
}

@MainActor @Test func unreadableFileIsKeptAsideNotOverwritten() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jindu-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let file = dir.appendingPathComponent("data.json")
    try Data("{ 壞掉的 json".utf8).write(to: file)

    let store = Store(directory: dir)
    #expect(store.data.projects.isEmpty)
    let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
    #expect(names.contains { $0.hasPrefix("data-讀不懂-") })
}

@Test func olderFilesWithMissingFieldsStillLoad() throws {
    let json = """
    {"projects":[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"舊","groups":[
      {"id":"7F9619FF-8B86-D011-B42D-00C04FC964FF","name":"一","kind":"grid","start":1,"end":3,"stamps":{"2":"2026-11-13T10:00:00Z"}}
    ]}]}
    """
    let data = try Persistence.decoder().decode(AppData.self, from: Data(json.utf8))
    #expect(data.projects[0].groups[0].doneCount == 1)
    #expect(data.settings.dayStartHour == 0)
}
