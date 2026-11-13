import Foundation

public enum QuotaPeriod: String, Codable, Sendable {
    case week
    case month
}

/// 循環任務的頻率。
public enum RoutineRule: Equatable, Sendable {
    /// 每天一次
    case daily
    /// 每週固定幾天。數字是 Calendar 的 weekday：1＝週日，2＝週一 … 7＝週六
    case weekdays([Int])
    /// 一個週期（週／月）內做夠 N 次，哪天做都行
    case quota(times: Int, per: QuotaPeriod)
    /// 從起始日算起每隔 N 天一次
    case everyN(days: Int)
}

extension RoutineRule: Codable {
    enum CodingKeys: String, CodingKey { case type, days, times, per }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "weekdays":
            self = .weekdays(try c.decode([Int].self, forKey: .days))
        case "quota":
            self = .quota(times: try c.decode(Int.self, forKey: .times), per: try c.decode(QuotaPeriod.self, forKey: .per))
        case "everyN":
            self = .everyN(days: try c.decode(Int.self, forKey: .days))
        default:
            self = .daily
        }
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .daily:
            try c.encode("daily", forKey: .type)
        case .weekdays(let days):
            try c.encode("weekdays", forKey: .type)
            try c.encode(days, forKey: .days)
        case .quota(let times, let per):
            try c.encode("quota", forKey: .type)
            try c.encode(times, forKey: .times)
            try c.encode(per, forKey: .per)
        case .everyN(let days):
            try c.encode("everyN", forKey: .type)
            try c.encode(days, forKey: .days)
        }
    }
}

public struct Routine: Identifiable, Equatable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var rule: RoutineRule
    /// 從哪天開始算（「每隔 N 天」以它為起點；歷史也不會往它之前追）
    public var startDate: Date
    /// 每次完成的時間
    public var log: [Date]

    public init(id: UUID = UUID(), title: String, rule: RoutineRule, startDate: Date = Date(), log: [Date] = []) {
        self.id = id
        self.title = title
        self.rule = rule
        self.startDate = startDate
        self.log = log
    }
}

/// 某個循環任務在「現在」的狀態。
public struct RoutineState: Equatable, Sendable {
    /// 今天輪到它嗎。「做夠 N 次」型在週期內一直算輪到。
    public let isDueToday: Bool
    /// 已做次數：按日排的是今天做了沒（0/1），「做夠 N 次」型是本週期做了幾次
    public let done: Int
    public let target: Int
    /// 今天沒輪到時，下一次是哪天
    public let nextDue: Date?
    /// 最近幾次（或幾個週期）做沒做，從舊到新，不含今天／本週期
    public let history: [Bool]
    /// 連續完成幾次（今天／本週期做完了就算進去，還沒做不算斷）
    public let streak: Int

    public var isSatisfied: Bool { done >= target }
    /// 今天該做而還沒做完
    public var needsAttention: Bool { isDueToday && !isSatisfied }
}

extension Routine {
    public func isDue(on day: Date, clock: DayClock) -> Bool {
        let startDay = clock.day(of: startDate)
        switch rule {
        case .daily:
            return true
        case .weekdays(let days):
            return days.contains(clock.calendar.component(.weekday, from: day))
        case .quota:
            return true
        case .everyN(let n):
            let gap = clock.calendar.dateComponents([.day], from: startDay, to: day).day ?? 0
            return gap >= 0 && gap % max(1, n) == 0
        }
    }

    public func state(now: Date, clock: DayClock, historyCount: Int = 7) -> RoutineState {
        let cal = clock.calendar
        let today = clock.day(of: now)
        let startDay = min(clock.day(of: startDate), today)
        let logDays = log.map { clock.day(of: $0) }

        if case .quota(let times, let per) = rule {
            let target = max(1, times)
            let unit: Calendar.Component = per == .week ? .weekOfYear : .month
            func interval(_ day: Date) -> DateInterval {
                cal.dateInterval(of: unit, for: day) ?? DateInterval(start: day, duration: 86400)
            }
            func count(_ iv: DateInterval) -> Int {
                logDays.reduce(0) { $0 + (($1 >= iv.start && $1 < iv.end) ? 1 : 0) }
            }
            let current = interval(today)
            let done = count(current)
            let firstStart = interval(startDay).start

            var history: [Bool] = []
            var streak = done >= target ? 1 : 0
            var streakOpen = true
            var cursor = current.start
            for _ in 0..<120 {
                guard let before = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
                let iv = interval(before)
                guard iv.start >= firstStart else { break }
                let met = count(iv) >= target
                if history.count < historyCount { history.append(met) }
                if streakOpen {
                    if met { streak += 1 } else { streakOpen = false }
                }
                if history.count >= historyCount && !streakOpen { break }
                cursor = iv.start
            }
            return RoutineState(isDueToday: true, done: done, target: target, nextDue: nil,
                                history: history.reversed(), streak: streak)
        }

        // 按日排的三種：每天、每週固定幾天、每隔 N 天
        let logSet = Set(logDays)
        let dueToday = isDue(on: today, clock: clock)
        let doneToday = dueToday && logSet.contains(today)

        var history: [Bool] = []
        var streak = doneToday ? 1 : 0
        var streakOpen = true
        var day = today
        for _ in 0..<1500 {
            guard let previous = cal.date(byAdding: .day, value: -1, to: day), previous >= startDay else { break }
            day = previous
            guard isDue(on: day, clock: clock) else { continue }
            let met = logSet.contains(day)
            if history.count < historyCount { history.append(met) }
            if streakOpen {
                if met { streak += 1 } else { streakOpen = false }
            }
            if history.count >= historyCount && !streakOpen { break }
        }

        var next: Date?
        if !dueToday {
            for offset in 1...400 {
                guard let candidate = cal.date(byAdding: .day, value: offset, to: today) else { break }
                if isDue(on: candidate, clock: clock) {
                    next = candidate
                    break
                }
            }
        }

        return RoutineState(isDueToday: dueToday, done: doneToday ? 1 : 0, target: 1, nextDue: next,
                            history: history.reversed(), streak: streak)
    }
}
