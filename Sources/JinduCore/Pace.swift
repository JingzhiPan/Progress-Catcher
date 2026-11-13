import Foundation

/// 有截止日時的配速：還剩多少、還剩幾天、每天要做多少、有沒有落後。
public struct Pace: Equatable, Sendable {
    public enum Status: Sendable {
        case complete
        /// 截止日已過還沒做完
        case overdue
        /// 比「從設定截止日那天起平均每天做一樣多」的進度慢
        case behind
        case onTrack
    }

    public let remaining: Int
    /// 還剩幾天，含今天。截止日當天是 1，過了是 0 或負數。
    public let daysLeft: Int
    /// 每天要做多少，按今天開始時的剩餘量算（今天做掉的不會讓它變小）
    public let perDay: Int
    public let doneToday: Int
    /// 落後均速多少個；沒落後是 0
    public let lag: Int
    public let status: Status

    public var needsAttention: Bool { status == .overdue || status == .behind }

    /// - Parameters:
    ///   - deadline: 截止日（那一天結束前做完）
    ///   - setAt: 截止日是哪天設的；均速從那天起算。沒有就當作今天才設。
    public static func compute(total: Int, doneDates: [Date], deadline: Date, setAt: Date?,
                               now: Date, clock: DayClock) -> Pace {
        let cal = clock.calendar
        let today = clock.day(of: now)
        let dueDay = cal.startOfDay(for: deadline)
        let remaining = max(0, total - doneDates.count)
        let daysLeft = (cal.dateComponents([.day], from: today, to: dueDay).day ?? 0) + 1
        let doneToday = clock.count(of: doneDates, onDayOf: now)

        if total > 0 && remaining == 0 {
            return Pace(remaining: 0, daysLeft: daysLeft, perDay: 0, doneToday: doneToday, lag: 0, status: .complete)
        }
        if daysLeft <= 0 {
            return Pace(remaining: remaining, daysLeft: daysLeft, perDay: remaining, doneToday: doneToday,
                        lag: remaining, status: remaining > 0 ? .overdue : .onTrack)
        }

        let startOfTodayRemaining = remaining + doneToday
        let perDay = (startOfTodayRemaining + daysLeft - 1) / daysLeft

        // 均速線：從設定那天到截止日，每天做一樣多；到昨天為止應該做完多少。
        let startDay = min(clock.day(of: setAt ?? now), today)
        let span = (cal.dateComponents([.day], from: startDay, to: dueDay).day ?? 0) + 1
        let elapsed = cal.dateComponents([.day], from: startDay, to: today).day ?? 0
        let doneBeforeStart = doneDates.reduce(0) { $0 + (clock.day(of: $1) < startDay ? 1 : 0) }
        let work = max(0, total - doneBeforeStart)
        let expected = span > 0 ? work * elapsed / span : 0
        let actual = doneDates.count - doneBeforeStart
        let lag = max(0, expected - actual)

        return Pace(remaining: remaining, daysLeft: daysLeft, perDay: perDay, doneToday: doneToday,
                    lag: lag, status: lag > 0 ? .behind : .onTrack)
    }
}

/// 今天輪到的一個循環任務（做了沒做都列出來）。
public struct TodayRoutine: Identifiable, Equatable, Sendable {
    public let projectID: UUID
    public let projectName: String
    public let groupID: UUID
    public let routine: Routine
    public let state: RoutineState
    public var id: UUID { routine.id }
}

/// 一個還沒做完的截止日（項目的或分組的）。
public struct DeadlineInfo: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let projectID: UUID
    public let title: String
    public let deadline: Date
    public let pace: Pace
}

extension TrackGroup {
    public func pace(now: Date, clock: DayClock) -> Pace? {
        guard let deadline, kind != .routine else { return nil }
        return Pace.compute(total: total, doneDates: doneDates, deadline: deadline, setAt: deadlineSetAt, now: now, clock: clock)
    }
}

extension Project {
    public func pace(now: Date, clock: DayClock) -> Pace? {
        guard let deadline else { return nil }
        return Pace.compute(total: total, doneDates: doneDates, deadline: deadline, setAt: deadlineSetAt, now: now, clock: clock)
    }

    /// 這個項目裡還沒做完的截止日，最近的在前。項目自己的和各分組的都算。
    public func openDeadlines(now: Date, clock: DayClock) -> [DeadlineInfo] {
        var out: [DeadlineInfo] = []
        if let deadline, let pace = pace(now: now, clock: clock), pace.status != .complete, total > 0 {
            out.append(DeadlineInfo(id: id, projectID: id, title: name, deadline: deadline, pace: pace))
        }
        for group in groups {
            if let deadline = group.deadline, let pace = group.pace(now: now, clock: clock),
               pace.status != .complete, group.total > 0 {
                out.append(DeadlineInfo(id: group.id, projectID: id, title: "\(name) · \(group.name)", deadline: deadline, pace: pace))
            }
        }
        return out.sorted { $0.deadline < $1.deadline }
    }
}

extension AppData {
    /// 今天輪到的所有循環任務（只看沒歸檔的項目）。
    public func todayRoutines(now: Date, clock: DayClock) -> [TodayRoutine] {
        var out: [TodayRoutine] = []
        for project in projects where !project.archived {
            for group in project.groups where group.kind == .routine {
                for routine in group.routines {
                    let state = routine.state(now: now, clock: clock)
                    if state.isDueToday {
                        out.append(TodayRoutine(projectID: project.id, projectName: project.name,
                                                groupID: group.id, routine: routine, state: state))
                    }
                }
            }
        }
        return out
    }

    public func openDeadlines(now: Date, clock: DayClock) -> [DeadlineInfo] {
        projects.filter { !$0.archived }
            .flatMap { $0.openDeadlines(now: now, clock: clock) }
            .sorted { $0.deadline < $1.deadline }
    }

    /// 需要提醒的事有幾件：今天該做沒做的循環任務，加上落後或過期的截止日。
    public func attentionCount(now: Date, clock: DayClock) -> Int {
        todayRoutines(now: now, clock: clock).filter(\.state.needsAttention).count
            + openDeadlines(now: now, clock: clock).filter(\.pace.needsAttention).count
    }
}
