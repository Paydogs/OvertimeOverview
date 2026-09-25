//
//  WorktimeMathTests.swift
//  OvertimeOverview
//

import Foundation
import Testing
@testable import OvertimeOverview

struct WorktimeMathTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Budapest")!
        return calendar
    }()

    static func date(_ hour: Int, _ minute: Int, _ second: Int = 0, day: Int = 23, month: Int = 9, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    static func session(_ start: Date, _ end: Date?) -> WorkSession {
        WorkSession(id: UUID(), start: start, end: end)
    }

    // Review Focus 1: a session crossing midnight stays in its start day.
    @Test func midnightCrossingSessionStaysInStartDay() {
        let start = Self.date(22, 0, day: 23)
        let crossing = Self.session(start, Self.date(2, 0, day: 24))
        let days = WorktimeMath.groupSessions([crossing], calendar: Self.calendar)
        #expect(days.count == 1)
        #expect(Self.calendar.isDate(days[0].dayStart, inSameDayAs: start))
    }

    // Review Focus 2: DST end (2026-10-25, 03:00 → 02:00 in Budapest) still
    // groups both sessions into their local midnights.
    @Test func dstDayBoundary() {
        let before = Self.session(Self.date(1, 0, day: 25, month: 10), nil)
        let after = Self.session(Self.date(4, 0, day: 25, month: 10), nil)
        let days = WorktimeMath.groupSessions([before, after], calendar: Self.calendar)
        #expect(days.count == 1)
        #expect(Self.calendar.isDate(days[0].dayStart, inSameDayAs: Self.date(1, 0, day: 25, month: 10)))
    }

    @Test func netWorktimeNeverNegative() {
        #expect(WorktimeMath.netWorktime(presence: 1200, lunch: 1800) == 0)
        #expect(WorktimeMath.netWorktime(presence: 3600, lunch: 1800) == 1800)
    }

    @Test func overtimeDisplayGating() {
        #expect(WorktimeMath.showsOvertime(overtime: 300, dayEnded: false))
        #expect(!WorktimeMath.showsOvertime(overtime: -300, dayEnded: false))
        #expect(WorktimeMath.showsOvertime(overtime: -300, dayEnded: true))
        #expect(!WorktimeMath.showsOvertime(overtime: 0, dayEnded: true))
    }

    @Test func projectedFinishAddsRemaining() {
        let now = Self.date(12, 0)
        let finish = WorktimeMath.projectedFinish(now: now, presence: 3 * 3600, target: 8 * 3600)
        #expect(finish == now.addingTimeInterval(5 * 3600))
    }

    @Test func monthOvertimeIsSigned() {
        // Two days: +1h and -30m net against an 8h target → +30m month overtime
        let monthOvertime = WorktimeMath.monthOvertime(netPerDay: [9 * 3600, 7.5 * 3600], workPerDay: 8 * 3600)
        #expect(monthOvertime == 1800)
    }

    @Test func historyCandidatesExcludesTodayUnlessEnded() {
        let today = Self.date(12, 0, day: 23)
        let yesterday = Self.date(12, 0, day: 22)
        let days = [
            WorkDay(dayStart: Self.calendar.startOfDay(for: today), sessions: []),
            WorkDay(dayStart: Self.calendar.startOfDay(for: yesterday), sessions: []),
        ]
        let notEnded = WorktimeMath.historyCandidates(days: days, now: today, dayEnded: false, calendar: Self.calendar)
        #expect(notEnded.count == 1)
        let ended = WorktimeMath.historyCandidates(days: days, now: today, dayEnded: true, calendar: Self.calendar)
        #expect(ended.count == 2)
    }

    @Test func groupByMonthSortsNewestFirst() {
        let aug = WorkDay(dayStart: Self.date(1, 0, day: 1, month: 8), sessions: [])
        let sep = WorkDay(dayStart: Self.date(1, 0, day: 1, month: 9), sessions: [])
        let groups = WorktimeMath.groupByMonth([aug, sep], calendar: Self.calendar)
        #expect(groups.count == 2)
        #expect(Self.calendar.isDate(groups[0].monthStart, inSameDayAs: sep.dayStart))
    }

    @Test func punchDateKeepsSeconds() {
        let day = Self.calendar.startOfDay(for: Self.date(12, 0, day: 23))
        let punched = WorktimeMath.punchDate(onDay: day, hour: 9, minute: 12, second: 34, calendar: Self.calendar)
        let comps = Self.calendar.dateComponents([.hour, .minute, .second], from: punched)
        #expect(comps.hour == 9 && comps.minute == 12 && comps.second == 34)
    }

    @Test func statusTransitions() {
        let open = Self.session(Self.date(9, 12), nil)
        #expect(WorktimeMath.status(todayPresence: 3600, openSession: open, dayEnded: false) == .atOffice(since: open.start))
        #expect(WorktimeMath.status(todayPresence: 3600, openSession: nil, dayEnded: true) == .doneForToday)
        #expect(WorktimeMath.status(todayPresence: 3600, openSession: nil, dayEnded: false) == .onBreak)
        #expect(WorktimeMath.status(todayPresence: 0, openSession: nil, dayEnded: false) == .notAtOffice)
    }

    @Test func clockInLabelVariants() {
        #expect(WorktimeMath.clockInLabel(todayPresence: 3600, dayEnded: false) == true)  // "Clock back in"
        #expect(WorktimeMath.clockInLabel(todayPresence: 3600, dayEnded: true) == false)   // ended → "Clock in"
        #expect(WorktimeMath.clockInLabel(todayPresence: 0, dayEnded: false) == false)     // fresh → "Clock in"
    }

    @Test func formatterShapes() {
        #expect(Formatters.elapsed(7 * 3600 + 32 * 60 + 10) == "7:32:10")
        #expect(Formatters.duration(-(2 * 3600 + 5 * 60)).hasPrefix("-"))
        #expect(Formatters.shortDuration(25 * 60).contains("25"))
        #expect(Formatters.shortDuration(75 * 60).contains("h"))
    }
}