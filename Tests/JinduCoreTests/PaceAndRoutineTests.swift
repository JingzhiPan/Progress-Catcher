import Foundation
import Testing
@testable import JinduCore

private func utc() -> Calendar {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    c.firstWeekday = 1 // 週日起算；2026-11-13 所在的週是 11/08–11/14
    return c
}

private func date(_ s: String) -> Date { ISO8601DateFormatter().date(from: s)! }

/// 2026-11-13 是星期五。
private let now = date("2026-11-13T12:00:00Z")
private let clock = DayClock(startHour: 0, calendar: utc())
private func daysAgo(_ n: Int, hour: Int = 10) -> Date {
    date("2026-11-13T00:00:00Z").addingTimeInterval(Double(-n * 86400 + hour * 3600))
}

// MARK: 配速

@Test func paceSplitsRemainingEvenlyOverDaysLeft() {
    // 今天設、9 天後截止 → 含今天共 10 天
    let p = Pace.compute(total: 100, doneDates: [], deadline: date("2026-11-22T00:00:00Z"), setAt: now, now: now, clock: clock)
    #expect(p.remaining == 100)
    #expect(p.daysLeft == 10)
    #expect(p.perDay == 10)
    #expect(p.status == .onTrack)
    #expect(p.lag == 0)

    // 除不盡要進位：7 個分 3 天 → 每天 3
    let q = Pace.compute(total: 7, doneDates: [], deadline: date("2026-11-15T00:00:00Z"), setAt: now, now: now, clock: clock)
    #expect(q.daysLeft == 3)
    #expect(q.perDay == 3)

    // 截止日就是今天 → 剩 1 天，全部今天做
    let r = Pace.compute(total: 7, doneDates: [], deadline: date("2026-11-13T00:00:00Z"), setAt: now, now: now, clock: clock)
    #expect(r.daysLeft == 1)
    #expect(r.perDay == 7)
}

@Test func paceFlagsFallingBehindTheEvenLine() {
    // 5 天前設、4 天後截止 → 計畫共 10 天，到昨天應做完一半（50）
    let deadline = date("2026-11-17T00:00:00Z")
    let setAt = daysAgo(5)
    let done = (0..<17).map { _ in daysAgo(2) } + (0..<3).map { _ in now }
    let p = Pace.compute(total: 100, doneDates: done, deadline: deadline, setAt: setAt, now: now, clock: clock)
    #expect(p.remaining == 80)
    #expect(p.daysLeft == 5)
    #expect(p.doneToday == 3)
    #expect(p.perDay == 17) // 今天開始時剩 83，83/5 進位
    #expect(p.lag == 30)
    #expect(p.status == .behind)
    #expect(p.needsAttention)

    // 今天補上就不算落後了
    let caughtUp = done + (0..<30).map { _ in now }
    let q = Pace.compute(total: 100, doneDates: caughtUp, deadline: deadline, setAt: setAt, now: now, clock: clock)
    #expect(q.status == .onTrack)
    #expect(q.lag == 0)
}

@Test func workDoneBeforeTheDeadlineWasSetIsNotExpectedAgain() {
    // 設截止日之前已做 40；剩下 60 分 10 天，到昨天應做 30，實際做了 30 → 沒落後
    let done = (0..<40).map { _ in daysAgo(20) } + (0..<30).map { _ in daysAgo(1) }
    let p = Pace.compute(total: 100, doneDates: done, deadline: date("2026-11-17T00:00:00Z"), setAt: daysAgo(5), now: now, clock: clock)
    #expect(p.lag == 0)
    #expect(p.status == .onTrack)
    #expect(p.perDay == 6)
}

@Test func paceOverdueAndComplete() {
    let overdue = Pace.compute(total: 10, doneDates: [daysAgo(3)], deadline: date("2026-11-11T00:00:00Z"), setAt: daysAgo(6), now: now, clock: clock)
    #expect(overdue.status == .overdue)
    #expect(overdue.daysLeft == -1)
    #expect(overdue.remaining == 9)

    let complete = Pace.compute(total: 2, doneDates: [daysAgo(3), daysAgo(1)], deadline: date("2026-11-11T00:00:00Z"), setAt: daysAgo(6), now: now, clock: clock)
    #expect(complete.status == .complete)
    #expect(!complete.needsAttention)
}

// MARK: 循環任務

@Test func dailyRoutineHistoryAndStreak() {
    // 5 天前開始；前 4 天做了、前 3 天漏了、前 2 天和昨天做了
    var r = Routine(title: "背單字", rule: .daily, startDate: daysAgo(5), log: [daysAgo(4), daysAgo(2), daysAgo(1)])
    var s = r.state(now: now, clock: clock)
    #expect(s.isDueToday)
    #expect(s.needsAttention)
    #expect(s.history == [false, true, false, true, true]) // 從舊到新，不追到開始日之前
    #expect(s.streak == 2) // 今天還沒做不算斷

    r.log.append(now)
    s = r.state(now: now, clock: clock)
    #expect(s.isSatisfied)
    #expect(!s.needsAttention)
    #expect(s.streak == 3)
}

@Test func weekdayRoutineOnlyDueOnChosenDays() {
    // 週一、週三；今天是週五
    let r = Routine(title: "讀書會", rule: .weekdays([2, 4]), startDate: daysAgo(14), log: [daysAgo(2)]) // 週三做了
    let s = r.state(now: now, clock: clock)
    #expect(!s.isDueToday)
    #expect(!s.needsAttention)
    #expect(s.nextDue == date("2026-11-16T00:00:00Z")) // 下週一
    #expect(s.history.suffix(2) == [false, true]) // 週一漏了、週三做了
    #expect(s.streak == 1)

    let onWednesday = r.state(now: date("2026-11-11T09:00:00Z"), clock: clock)
    #expect(onWednesday.isDueToday)
    #expect(onWednesday.isSatisfied)
}

@Test func everyNDaysCountsFromStartDate() {
    let r = Routine(title: "澆花", rule: .everyN(days: 3), startDate: date("2026-11-10T08:00:00Z"), log: [date("2026-11-10T09:00:00Z")])
    let today = r.state(now: now, clock: clock) // 11/13 = 起始日 + 3
    #expect(today.isDueToday)
    #expect(today.history == [true])
    #expect(today.streak == 1)

    let tomorrow = r.state(now: date("2026-11-14T12:00:00Z"), clock: clock)
    #expect(!tomorrow.isDueToday)
    #expect(tomorrow.nextDue == date("2026-11-16T00:00:00Z"))
    #expect(tomorrow.history == [true, false]) // 11/13 那次漏了
}

@Test func quotaRoutineCountsWithinThePeriod() {
    // 每週 3 次。前前週 0 次、上週 3 次、本週目前 2 次
    var r = Routine(title: "田野筆記", rule: .quota(times: 3, per: .week), startDate: date("2026-10-28T08:00:00Z"), log: [
        date("2026-11-02T10:00:00Z"), date("2026-11-04T10:00:00Z"), date("2026-11-06T10:00:00Z"),
        date("2026-11-09T10:00:00Z"), date("2026-11-10T10:00:00Z"),
    ])
    var s = r.state(now: now, clock: clock)
    #expect(s.isDueToday)
    #expect(s.done == 2)
    #expect(s.target == 3)
    #expect(s.needsAttention)
    #expect(s.history == [false, true])
    #expect(s.streak == 1)

    r.log.append(now)
    s = r.state(now: now, clock: clock)
    #expect(s.isSatisfied)
    #expect(s.streak == 2)

    // 每月型：同一批記錄，11 月共 6 次
    r.rule = .quota(times: 8, per: .month)
    s = r.state(now: now, clock: clock)
    #expect(s.done == 6)
    #expect(s.history == [false]) // 10 月（開始那個月）0 次
}

@Test func routineRuleSurvivesEncoding() throws {
    let rules: [RoutineRule] = [.daily, .weekdays([2, 4, 6]), .quota(times: 3, per: .week), .quota(times: 10, per: .month), .everyN(days: 14)]
    for rule in rules {
        let raw = try Persistence.encoder().encode(Routine(title: "x", rule: rule, startDate: date("2026-11-01T00:00:00Z")))
        #expect(try Persistence.decoder().decode(Routine.self, from: raw).rule == rule)
    }
}

// MARK: Store

@MainActor @Test func tappingRoutinesLogsAndUndoes() {
    let store = Store(directory: nil)
    let p = store.addProject(name: "日常")
    let g = store.addRoutineGroup(project: p, name: "")!
    #expect(store.project(p)?.groups[0].name == "循環任務")

    let daily = store.addRoutine("背單字", rule: .daily, group: g, project: p)!
    let weekly = store.addRoutine("田野筆記", rule: .quota(times: 2, per: .week), group: g, project: p)!
    #expect(store.addRoutine("壞的", rule: .weekdays([]), group: g, project: p) == nil)
    #expect(store.addRoutine("壞的", rule: .everyN(days: 1), group: g, project: p) == nil)
    #expect(store.data.attentionCount(now: Date(), clock: store.clock) == 2)

    func logCount(_ id: UUID) -> Int { store.project(p)!.groups[0].routines.first { $0.id == id }!.log.count }

    store.tapRoutine(daily, group: g, project: p)
    #expect(logCount(daily) == 1)
    #expect(store.data.attentionCount(now: Date(), clock: store.clock) == 1)
    store.tapRoutine(daily, group: g, project: p) // 做完了再點 = 撤銷
    #expect(logCount(daily) == 0)

    store.tapRoutine(weekly, group: g, project: p)
    store.tapRoutine(weekly, group: g, project: p)
    #expect(logCount(weekly) == 2)
    store.tapRoutine(weekly, group: g, project: p) // 滿了再點 = 撤銷一次
    #expect(logCount(weekly) == 1)
    store.undoRoutine(weekly, group: g, project: p)
    #expect(logCount(weekly) == 0)

    // 循環任務不算進項目的「已完成／總數」
    #expect(store.project(p)?.total == 0)

    // 只有循環任務的項目不搶菜單欄：就算它最近剛操作過，數字還是跟著有總數的項目
    let book = store.addProject(name: "書稿", now: Date().addingTimeInterval(-3600))
    store.addGridGroup(project: book, name: "一", start: 1, end: 5)
    store.tapRoutine(daily, group: g, project: p)
    #expect(store.data.activeProjects.first?.id == p)
    #expect(store.data.focusProject?.id == book)
    store.deleteProject(book)
    #expect(store.data.focusProject?.id == p) // 沒有別的項目時才輪到它
    store.tapRoutine(daily, group: g, project: p)

    // 歸檔的項目不提醒
    store.setArchived(p, true)
    #expect(store.data.attentionCount(now: Date(), clock: store.clock) == 0)
    #expect(store.data.todayRoutines(now: Date(), clock: store.clock).isEmpty)
}

@MainActor @Test func deadlinesShowUpAsOpenUntilDone() {
    let store = Store(directory: nil)
    let p = store.addProject(name: "譯稿")
    let g = store.addGridGroup(project: p, name: "第三章", start: 1, end: 4)!
    let yesterday = Date().addingTimeInterval(-86400)
    let nextWeek = Date().addingTimeInterval(7 * 86400)

    store.setDeadline(nextWeek, project: p)
    store.setDeadline(yesterday, group: g, project: p)
    var open = store.data.openDeadlines(now: Date(), clock: store.clock)
    #expect(open.map(\.title) == ["譯稿 · 第三章", "譯稿"]) // 最近的在前
    #expect(open[0].pace.status == .overdue)
    #expect(store.data.attentionCount(now: Date(), clock: store.clock) == 1)
    #expect(store.project(p)?.deadlineSetAt != nil)

    for n in 1...4 { store.setStamp(n, done: true, group: g, project: p) }
    open = store.data.openDeadlines(now: Date(), clock: store.clock)
    #expect(open.isEmpty) // 做完了就不再列

    store.setDeadline(nil, project: p)
    #expect(store.project(p)?.deadline == nil)
    #expect(store.project(p)?.deadlineSetAt == nil)
}

@MainActor @Test func exportThenImportRestoresEverything() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("jindu-test-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: dir) }

    let store = Store(directory: dir)
    let p = store.addProject(name: "譯稿", now: date("2026-11-01T10:00:00Z"))
    let g = store.addGridGroup(project: p, name: "一", start: 1, end: 9)!
    store.setStamp(3, done: true, group: g, project: p, now: date("2026-11-12T10:00:00Z"))
    store.setDeadline(date("2026-11-20T00:00:00Z"), group: g, project: p, now: date("2026-11-10T10:00:00Z"))
    let rg = store.addRoutineGroup(project: p, name: "每日")!
    let r = store.addRoutine("背單字", rule: .weekdays([2, 4]), group: rg, project: p, now: date("2026-11-01T10:00:00Z"))!
    store.setReminder(.notification)
    store.setNotifyTime(hour: 20, minute: 30)
    let snapshot = store.data
    let exported = try store.exportData()

    store.deleteProject(p)
    store.setReminder(.off)
    #expect(store.data.projects.isEmpty)

    try store.importData(exported)
    #expect(store.data == snapshot)
    #expect(store.project(p)?.groups[1].routines.first?.id == r)

    // 取代之前留了底
    let backups = try FileManager.default.contentsOfDirectory(atPath: dir.appendingPathComponent("backups").path)
    #expect(backups.contains { $0.hasPrefix("匯入前-") })

    // 不相干的 JSON 不會把資料清空
    #expect(throws: Store.ImportError.notRecognized) { try store.importData(Data(#"{"foo": 1}"#.utf8)) }
    #expect(throws: Store.ImportError.notRecognized) { try store.importData(Data("不是 json".utf8)) }
    #expect(store.data == snapshot)
}
