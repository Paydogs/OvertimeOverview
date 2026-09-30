//
//  WorktimeMath.swift
//  OvertimeOverview
//

import Foundation

/// Pure MagniTools-parity business rules. No state, no side effects —
/// views and the widget share these.
enum WorktimeMath {
    static func startOfDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }

    static func startOfMonth(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
    }

    static func groupSessions(_ sessions: [WorkSession], calendar: Calendar) -> [WorkDay] {
        let grouped = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.start) }
        return grouped
            .map { WorkDay(dayStart: $0.key, sessions: $0.value.sorted { $0.start < $1.start }) }
            .sorted { $0.dayStart > $1.dayStart }
    }

    static func todaysSessions(_ sessions: [WorkSession], now: Date, calendar: Calendar) -> [WorkSession] {
        let dayStart = calendar.startOfDay(for: now)
        return sessions.filter { $0.start >= dayStart }.sorted { $0.start > $1.start }
    }

    static func presence(_ sessions: [WorkSession], now: Date) -> TimeInterval {
        sessions.reduce(0) { $0 + $1.duration(now: now) }
    }

    static func netWorktime(presence: TimeInterval, lunch: TimeInterval) -> TimeInterval {
        max(0, presence - lunch)
    }

    static func showsOvertime(overtime: TimeInterval, dayEnded: Bool) -> Bool {
        overtime > 0 || (overtime < 0 && dayEnded)
    }

    static func projectedFinish(now: Date, presence: TimeInterval, target: TimeInterval) -> Date {
        now.addingTimeInterval(target - presence)
    }

    static func monthOvertime(netPerDay: [TimeInterval], workPerDay: TimeInterval) -> TimeInterval {
        netPerDay.reduce(0) { $0 + ($1 - workPerDay) }
    }

    /// Past days, plus today when the day has ended or is still running with an
    /// open session — so the workday in progress is visible on History too.
    static func historyCandidates(
        days: [WorkDay], now: Date, dayEnded: Bool, isWorking: Bool, calendar: Calendar
    ) -> [WorkDay] {
        let today = calendar.startOfDay(for: now)
        let todayVisible = dayEnded || isWorking
        return days.filter { $0.dayStart < today || ($0.dayStart == today && todayVisible) }
    }

    static func groupByMonth(_ days: [WorkDay], calendar: Calendar) -> [(monthStart: Date, days: [WorkDay])] {
        let grouped = Dictionary(grouping: days) { startOfMonth($0.dayStart, calendar: calendar) }
        return grouped
            .map { (monthStart: $0.key, days: $0.value.sorted { $0.dayStart > $1.dayStart }) }
            .sorted { $0.monthStart > $1.monthStart }
    }

    static func punchDate(onDay day: Date, hour: Int, minute: Int, second: Int, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = second
        return calendar.date(from: components)!
    }

    enum TodayStatus: Equatable {
        case atOffice(since: Date)
        case doneForToday
        case onBreak
        case notAtOffice
    }

    static func status(todayPresence: TimeInterval, openSession: WorkSession?, dayEnded: Bool) -> TodayStatus {
        if let open = openSession { return .atOffice(since: open.start) }
        if dayEnded { return .doneForToday }
        if todayPresence > 0 { return .onBreak }
        return .notAtOffice
    }

    /// true → "Clock back in" (there is time today and the day isn't ended),
    /// false → "Clock in" (fresh day, or ended for today).
    static func clockInLabel(todayPresence: TimeInterval, dayEnded: Bool) -> Bool {
        todayPresence > 0 && !dayEnded
    }
}