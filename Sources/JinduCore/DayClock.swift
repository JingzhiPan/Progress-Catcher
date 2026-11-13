import Foundation

public struct DayCount: Equatable, Sendable {
    public let day: Date
    public let count: Int
}

/// 把時間點歸到「哪一天」。一天的起點可以不是午夜。
public struct DayClock: Sendable {
    public var startHour: Int
    public var calendar: Calendar

    public init(startHour: Int = 0, calendar: Calendar = .current) {
        self.startHour = min(max(startHour, 0), 23)
        self.calendar = calendar
    }

    /// 這個時間點所屬那一天的代表值（該日曆日的 00:00）。
    public func day(of date: Date) -> Date {
        calendar.startOfDay(for: date.addingTimeInterval(-Double(startHour) * 3600))
    }

    public func isSameDay(_ a: Date, _ b: Date) -> Bool { day(of: a) == day(of: b) }

    public func count(of dates: [Date], onDayOf now: Date) -> Int {
        let today = day(of: now)
        return dates.reduce(0) { $0 + (day(of: $1) == today ? 1 : 0) }
    }

    /// 兩個時間點相差幾「天」（按上面的日界線算）。
    public func daysBetween(_ earlier: Date, _ later: Date) -> Int {
        calendar.dateComponents([.day], from: day(of: earlier), to: day(of: later)).day ?? 0
    }

    /// 最近 `days` 天每天完成幾個，從舊到新，最後一項是今天。
    public func history(of dates: [Date], days: Int, now: Date) -> [DayCount] {
        let today = day(of: now)
        var buckets: [Date: Int] = [:]
        for d in dates { buckets[day(of: d), default: 0] += 1 }
        return (0..<max(days, 0)).reversed().compactMap { back in
            guard let d = calendar.date(byAdding: .day, value: -back, to: today) else { return nil }
            return DayCount(day: d, count: buckets[d] ?? 0)
        }
    }
}
