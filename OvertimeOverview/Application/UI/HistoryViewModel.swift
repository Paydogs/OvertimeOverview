//
//  HistoryViewModel.swift
//  OvertimeOverview
//

import Foundation
import Observation

/// Months rendered by the History screen, plus the expand/collapse state:
/// pure sums over the worktime model, so the view only formats and taps.
@MainActor
@Observable
final class HistoryViewModel {
    struct MonthSummary {
        let monthStart: Date
        let days: [WorkDay]
        let worktime: TimeInterval
        let overtime: TimeInterval
    }

    struct DaySummary {
        let inOffice: TimeInterval
        let net: TimeInterval
        let overtime: TimeInterval
    }

    private let worktime: WorktimeViewModel
    let settings: WorktimeSettings

    init(worktime: WorktimeViewModel, settings: WorktimeSettings) {
        self.worktime = worktime
        self.settings = settings
    }

    /// Expand/collapse state lives here, not in the view.
    var expandedMonths: Set<Date> = []

    func months(now: Date) -> [MonthSummary] {
        let candidates = WorktimeMath.historyCandidates(
            days: worktime.days,
            now: now,
            dayEnded: settings.endedToday(now: now),
            isWorking: worktime.openSession != nil,
            calendar: .current
        )
        return WorktimeMath.groupByMonth(candidates, calendar: .current).map { month in
            let netPerDay = month.days.map {
                WorktimeMath.netWorktime(presence: $0.inOffice(now: now), lunch: settings.lunchSeconds)
            }
            return MonthSummary(
                monthStart: month.monthStart,
                days: month.days,
                worktime: netPerDay.reduce(0, +),
                overtime: WorktimeMath.monthOvertime(netPerDay: netPerDay, workPerDay: settings.workSeconds)
            )
        }
    }

    /// Only the newest month is expanded by default; a later appearance never
    /// re-expands (matches the original `isEmpty` guard).
    func prepareInitialExpanded(_ months: [MonthSummary]) {
        guard expandedMonths.isEmpty, let first = months.first else { return }
        expandedMonths = [first.monthStart]
    }

    func toggle(month: Date) {
        if expandedMonths.contains(month) {
            expandedMonths.remove(month)
        } else {
            expandedMonths.insert(month)
        }
    }

    func summary(for day: WorkDay, now: Date) -> DaySummary {
        let inOffice = day.inOffice(now: now)
        let net = WorktimeMath.netWorktime(presence: inOffice, lunch: settings.lunchSeconds)
        return DaySummary(inOffice: inOffice, net: net, overtime: net - settings.workSeconds)
    }
}