//
//  HistoryView.swift
//  OvertimeOverview
//

import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var appModel
    @State private var expandedMonths: Set<Date> = []
    @State private var selectedDay: WorkDay?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            HistoryContentView(
                appModel: appModel,
                now: timeline.date,
                expandedMonths: $expandedMonths,
                selectedDay: $selectedDay
            )
        }
        .sheet(item: $selectedDay) { day in
            DaySessionsSheet(day: day, now: Date())
                .presentationDetents([.medium])
        }
    }
}

private struct HistoryContentView: View {
    let appModel: AppModel
    let now: Date
    @Binding var expandedMonths: Set<Date>
    @Binding var selectedDay: WorkDay?

    var body: some View {
        let settings = appModel.settings
        let calendar = Calendar.current
        let candidates = WorktimeMath.historyCandidates(
            days: appModel.viewModel.days,
            now: now,
            dayEnded: settings.endedToday(now: now),
            calendar: calendar
        )
        let months = WorktimeMath.groupByMonth(candidates, calendar: calendar)

        List {
            if months.isEmpty {
                Text(Keys.historyEmpty)
                    .foregroundStyle(.secondary)
            }
            ForEach(months, id: \.monthStart) { month in
                MonthSection(
                    month: month,
                    now: now,
                    lunch: settings.lunchSeconds,
                    work: settings.workSeconds,
                    isExpanded: expandedMonths.contains(month.monthStart),
                    toggle: {
                        if expandedMonths.contains(month.monthStart) {
                            expandedMonths.remove(month.monthStart)
                        } else {
                            expandedMonths.insert(month.monthStart)
                        }
                    },
                    onSelectDay: { selectedDay = $0 }
                )
            }
        }
        .scrollContentBackground(.hidden)
        .midnightBackdrop()
        .onAppear {
            // Only the newest month is expanded by default.
            if expandedMonths.isEmpty, let first = months.first {
                expandedMonths = [first.monthStart]
            }
        }
        .navigationTitle(Keys.tabHistory)
    }
}

private struct MonthSection: View {
    let month: (monthStart: Date, days: [WorkDay])
    let now: Date
    let lunch: TimeInterval
    let work: TimeInterval
    let isExpanded: Bool
    let toggle: () -> Void
    let onSelectDay: (WorkDay) -> Void

    var body: some View {
        Section {
            if isExpanded {
                ForEach(month.days) { day in
                    Button { onSelectDay(day) } label: { DayRow(day: day, now: now, lunch: lunch, work: work) }
                        .buttonStyle(.plain)
                        .listRowBackground(Color.clear)
                }
            }
        } header: {
            Button(action: toggle) { header }
                .buttonStyle(.plain)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .padding(.bottom, 6)
        }
    }

    private var header: some View {
        let netPerDay = month.days.map {
            WorktimeMath.netWorktime(presence: $0.inOffice(now: now), lunch: lunch)
        }
        let monthNet = netPerDay.reduce(0, +)
        let monthOvertime = WorktimeMath.monthOvertime(netPerDay: netPerDay, workPerDay: work)

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(Formatters.month(month.monthStart))
                    .font(.headline)
                    .foregroundStyle(Theme.accent)
                Spacer()
                Image(systemName: "chevron_right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            HStack {
                Text(Keys.historyMonthWorktime(Formatters.duration(monthNet)))
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Spacer()
                if monthOvertime > 0 {
                    Text(Keys.historyMonthOvertime(Formatters.duration(monthOvertime)))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.accent)
                } else if monthOvertime < 0 {
                    Text(Keys.historyMonthUndertime(Formatters.duration(monthOvertime)))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(Theme.undertime)
                }
            }
        }
        .padding(14)
        .glassCard(cornerRadius: 18)
        .contentShape(Rectangle())
    }
}

private struct DayRow: View {
    let day: WorkDay
    let now: Date
    let lunch: TimeInterval
    let work: TimeInterval

    var body: some View {
        let inOffice = day.inOffice(now: now)
        let net = WorktimeMath.netWorktime(presence: inOffice, lunch: lunch)
        let overtime = net - work

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Formatters.weekdayDay(day.dayStart))
                        .font(.body)
                    Text(Keys.historyInOfficeSessions(
                        Formatters.duration(inOffice),
                        day.sessions.count
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Formatters.duration(net)).bold().monospacedDigit()
                    if overtime != 0 {
                        Text(Formatters.shortDuration(overtime))
                            .font(.caption)
                            .foregroundStyle(overtime > 0 ? Theme.accent : Theme.undertime)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct DaySessionsSheet: View {
    let day: WorkDay
    let now: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if day.sessions.isEmpty {
                    Text(Keys.historyNoSessions)
                }
                ForEach(day.sessions) { session in
                    HStack {
                        Text(session.isOpen
                             ? "\(Formatters.clock(session.start)) – \(Keys.sessionNow)"
                             : "\(Formatters.clock(session.start)) – \(Formatters.clock(session.end!))")
                        Spacer()
                        Text(Formatters.duration(session.duration(now: now)))
                    }
                }
            }
            .navigationTitle(Formatters.weekdayDay(day.dayStart))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Keys.sessionClose) { dismiss() }
                }
            }
        }
    }
}