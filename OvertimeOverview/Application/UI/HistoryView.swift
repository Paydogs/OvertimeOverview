//
//  HistoryView.swift
//  OvertimeOverview
//

import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var appModel
    @State private var selectedDay: WorkDay?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            HistoryContentView(
                appModel: appModel,
                now: timeline.date,
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
    @Binding var selectedDay: WorkDay?

    var body: some View {
        let months = appModel.history.months(now: now)
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
                        appModel: appModel,
                        onSelectDay: { selectedDay = $0 }
                    )
                }
            }
            .padding(.horizontal, 16)
        }
        .contentMargins(.bottom, 24)
        .appBackdrop(.history)
        .onAppear {
            appModel.history.prepareInitialExpanded(months)
        }
    }
}

private struct MonthSection: View {
    let month: HistoryViewModel.MonthSummary
    let now: Date
    let appModel: AppModel
    let onSelectDay: (WorkDay) -> Void

    var body: some View {
        let isExpanded = appModel.history.expandedMonths.contains(month.monthStart)
        return VStack(spacing: 10) {
            Button(action: { appModel.history.toggle(month: month.monthStart) }) {
                summaryCard
            }
            .buttonStyle(.plain)
            if isExpanded {
                dayCard
            }
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 8) {
                Image(systemName: "chevron_right")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.monthTextSecondary)
                    .rotationEffect(.degrees(appModel.history.expandedMonths.contains(month.monthStart) ? 90 : 0))
                Text(Formatters.month(month.monthStart))
                    .font(.headline)
                    .foregroundStyle(Theme.monthText)
            }
            .padding(.top, 20)
            .padding(.horizontal, 20)

            HStack(alignment: .top, spacing: 0) {
                summaryColumn(caption: Keys.worktimeTitle, value: Formatters.duration(month.worktime))
                Spacer()
                RoundedRectangle(cornerRadius: 1)
                    .fill(Theme.monthText.opacity(0.22))
                    .frame(width: 1.5, height: 48)
                Spacer()
                summaryColumn(
                    caption: Keys.historyMonthOvertimeLabel,
                    value: Formatters.duration(month.overtime),
                    valueColor: month.overtime > 0 ? Theme.monthOvertime : Theme.negativeText
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .monthSurface(cornerRadius: 30)
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
                    summary: appModel.history.summary(for: day, now: now),
                    showsDivider: index > 0,
                    highlightChip: index == 0,
                    onSelect: { onSelectDay(day) }
                )
            }
        }
        .cardSurface(cornerRadius: 26)
    }
}

private struct DayRow: View {
    let day: WorkDay
    let summary: HistoryViewModel.DaySummary
    let showsDivider: Bool
    var highlightChip = false
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 14) {
                DayChip(date: day.dayStart, highlight: highlightChip)
                VStack(alignment: .leading, spacing: 3) {
                    Text(Formatters.weekday(day.dayStart))
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(Keys.historyInOfficeSessions(
                        Formatters.duration(summary.inOffice),
                        day.sessions.count
                    ))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(Formatters.duration(summary.net))
                        .font(.body.bold())
                        .monospacedDigit()
                        .foregroundStyle(.primary)
                    if summary.overtime != 0 {
                        Text(Formatters.shortDuration(summary.overtime))
                            .font(.footnote.bold())
                            .monospacedDigit()
                            .foregroundStyle(summary.overtime > 0 ? Theme.overtimeText : Theme.negativeText)
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
                    .fill(Theme.separator)
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

#Preview("Day sessions sheet") {
    DaySessionsSheet(
        day: WorkDay(
            dayStart: .now,
            sessions: [
                WorkSession(
                    id: UUID(),
                    start: .now.addingTimeInterval(-4 * 3600),
                    end: .now.addingTimeInterval(-2.5 * 3600)
                ),
                WorkSession(
                    id: UUID(),
                    start: .now.addingTimeInterval(-2 * 3600),
                    end: nil
                ),
            ]
        ),
        now: .now
    )
    .preferredColorScheme(.dark)
}