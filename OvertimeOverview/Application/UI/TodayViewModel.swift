//
//  TodayViewModel.swift
//  OvertimeOverview
//

import Foundation
import Observation

/// Everything the Today screen renders, derived from the worktime model.
/// Pure selectors — dates come in, values come out; nothing stored here.
@MainActor
@Observable
final class TodayViewModel {
    enum PunchKind { case clockIn, breakOut, endOfDay }

    private let worktime: WorktimeViewModel
    let settings: WorktimeSettings

    init(worktime: WorktimeViewModel, settings: WorktimeSettings) {
        self.worktime = worktime
        self.settings = settings
    }

    var openSession: WorkSession? { worktime.openSession }

    func sessions(now: Date) -> [WorkSession] {
        worktime.todaysSessions(now: now)
    }

    func presence(now: Date) -> TimeInterval {
        WorktimeMath.presence(sessions(now: now), now: now)
    }

    func netWorktime(now: Date) -> TimeInterval {
        WorktimeMath.netWorktime(presence: presence(now: now), lunch: settings.lunchSeconds)
    }

    func overtime(now: Date) -> TimeInterval {
        presence(now: now) - settings.officeTarget
    }

    func status(now: Date) -> WorktimeMath.TodayStatus {
        WorktimeMath.status(
            todayPresence: presence(now: now),
            openSession: openSession,
            dayEnded: settings.endedToday(now: now)
        )
    }

    /// When not at the office yet this is "if you clocked in now" — still a useful anchor.
    func projectedFinish(now: Date) -> Date {
        WorktimeMath.projectedFinish(now: now, presence: presence(now: now), target: settings.officeTarget)
    }

    /// Progress runs from the open session's arrival to the projected leave,
    /// so the ring completes exactly at the expected departure. Without an open
    /// session it falls back to presence vs. the daily target.
    func ringProgress(now: Date) -> Double {
        if let start = openSession?.start {
            let span = projectedFinish(now: now).timeIntervalSince(start)
            guard span > 0 else { return 0 }
            return (now.timeIntervalSince(start) / span).clampedToUnitInterval
        }
        let target = settings.officeTarget
        return (target > 0 ? presence(now: now) / target : 0).clampedToUnitInterval
    }

    func clockInLabel(now: Date) -> String {
        WorktimeMath.clockInLabel(
            todayPresence: presence(now: now),
            dayEnded: settings.endedToday(now: now)
        ) ? Keys.buttonClockBackIn : Keys.buttonClockIn
    }

    // MARK: - Actions

    /// Punch from the wheel picker: keeps the tap's real second, and a clock-out
    /// lands on the day the open session started (MagniTools parity).
    func punch(_ kind: PunchKind, picked: Date, tapTime: Date) async {
        let calendar = Calendar.current
        let baseDay: Date
        if kind == .clockIn {
            baseDay = calendar.startOfDay(for: tapTime)
        } else {
            baseDay = calendar.startOfDay(for: worktime.openSession?.start ?? tapTime)
        }
        let components = calendar.dateComponents([.hour, .minute], from: picked)
        let date = WorktimeMath.punchDate(
            onDay: baseDay,
            hour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: calendar.component(.second, from: tapTime),
            calendar: calendar
        )
        switch kind {
        case .clockIn:
            await worktime.clockIn(at: date)
            settings.clearEnded()
        case .breakOut:
            await worktime.clockOut(at: date)
            settings.clearEnded()
        case .endOfDay:
            await worktime.clockOut(at: date)
            settings.markEndedToday()
        }
    }

    /// Manual session entry from the header's + button (end > start validated by the sheet).
    func add(start: Date, end: Date) async {
        await worktime.add(start: start, end: end)
    }
}