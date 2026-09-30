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

        ScrollView {
            VStack(spacing: 16) {
                ScreenHeader(title: Keys.tabHistory)

                if months.isEmpty {
                    Text(Keys.historyEmpty)
                        .font(.subheadline)
                        .foregroundStyle(Theme.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 4)
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
            .padding(.horizontal, 16)
        }
        .appBackdrop()
        .onAppear {
            // Only the newest month is expanded by default.
            if expandedMonths.isEmpty, let first = months.first {
                expandedMonths = [first.monthStart]
            }
        }
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
        VStack(spacing: 10) {
            Button(action: toggle) { summaryCard }
                .buttonStyle(.plain)
            if isExpanded {
                dayCard
            }
        }
    }

    private var monthNet: TimeInterval {
        month.days.reduce(0) {
            $0 + WorktimeMath.netWorktime(presence: $1.inOffice(now: now), lunch: lunch)
        }
    }

    private var monthOvertime: TimeInterval {
        WorktimeMath.monthOvertime(
            netPerDay: month.days.map {
                WorktimeMath.netWorktime(presence: $0.inOffice(now: now), lunch: lunch)
            },
            workPerDay: work
        )
    }

    private var summaryCard: some View {
        let overtime = monthOvertime
        return VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "chevron_right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.monthTextSecondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                Text(Formatters.month(month.monthStart))
                    .font(.headline)
                    .foregroundStyle(Theme.monthText)
            }
            .padding(.top, 20)
            .padding(.horizontal, 20)

            HStack(alignment: .top, spacing: 0) {
                summaryColumn(caption: Keys.worktimeTitle, value: Formatters.duration(monthNet))
                Spacer()
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.monthText.opacity(0.22))
                    .frame(width: 1.5, height: 48)
                Spacer()
                summaryColumn(
                    caption: Keys.historyMonthOvertimeLabel,
                    value: Formatters.duration(overtime),
                    valueColor: overtime > 0 ? Theme.monthOvertime : Theme.undertime
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .monthSurface(cornerRadius: 26)
        .contentShape(Rectangle())
    }

    private func summaryColumn(caption: String, value: String, valueColor: Color? = nil) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption)
                .font(.subheadline)
                .foregroundStyle(Theme.monthTextSecondary)
            Text(value)
                .font(DisplayFont.timer(38))
                .monospacedDigit()
                .foregroundStyle(valueColor ?? Theme.monthText)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The month's days, newest first, in one card with hairline separators.
    private var dayCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(month.days.enumerated()), id: \.element.id) { index, day in
                DayRow(
                    day: day,
                    now: now,
                    lunch: lunch,
                    work: work,
                    showsDivider: index > 0,
                    onSelect: { onSelectDay(day) }
                )
            }
        }
        .cardSurface(cornerRadius: 22)
    }
}

private struct DayRow: View {
    let day: WorkDay
    let now: Date
    let lunch: TimeInterval
    let work: TimeInterval
    let showsDivider: Bool
    let onSelect: () -> Void

    var body: some View {
        let inOffice = day.inOffice(now: now)
        let net = WorktimeMath.netWorktime(presence: inOffice, lunch: lunch)
        let overtime = net - work

        return Button(action: onSelect) {
            HStack(spacing: 14) {
                DayChip(date: day.dayStart)
                VStack(alignment: .leading, spacing: 3) {
                    Text(Formatters.weekday(day.dayStart))
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(Keys.historyInOfficeSessions(
                        Formatters.duration(inOffice),
                        day.sessions.count
                    ))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(Formatters.duration(net))
                        .font(.body.bold())
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    if overtime != 0 {
                        Text(Formatters.shortDuration(overtime))
                            .font(.footnote.bold())
                            .monospacedDigit()
                            .foregroundStyle(overtime > 0 ? Theme.overtime : Theme.undertime)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            if showsDivider {
                Rectangle()
                    .fill(Theme.cardStroke)
                    .frame(height: 1)
            }
        }
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
// MARK: - Previews

#Preview("History") {
    HistoryView()
        .environment(previewAppModel(seed: .history))
        .preferredColorScheme(.dark)
}

#Preview("History — light") {
    HistoryView()
        .environment(previewAppModel(seed: .history))
        .preferredColorScheme(.light)
}