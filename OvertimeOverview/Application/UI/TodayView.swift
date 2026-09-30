//
//  TodayView.swift
//  OvertimeOverview
//

import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var appModel
    @State private var punchTarget: PunchTarget?

    /// Which punch the time-picker sheet is configuring; `now` is captured so
    /// the picked time keeps the real second of the tap moment.
    struct PunchTarget: Identifiable {
        let kind: TodayViewModel.PunchKind
        let now: Date
        var id: String { "\(kind)" }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            TodayContentView(
                appModel: appModel,
                now: timeline.date,
                punchTarget: $punchTarget
            )
        }
        .sheet(item: $punchTarget) { target in
            PunchTimePicker(target: target, appModel: appModel)
        }
    }
}

private struct TodayContentView: View {
    let appModel: AppModel
    let now: Date
    @Binding var punchTarget: TodayView.PunchTarget?
    @State private var showingAdd = false

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                ScreenHeader(title: Keys.tabToday, caption: Formatters.longWeekdayDay(now)) {
                    RoundIconButton(systemImage: "plus") {
                        HapticsController.play(appModel.haptics.settings)
                        showingAdd = true
                    }
                }

                timeRing

                if appModel.today.status(now: now) != .notAtOffice {
                    statusPill
                }

                statTiles

                SessionSection(now: now, appModel: appModel)

                actionButtons()
            }
            .padding(.horizontal, 16)
        }
        .contentMargins(.bottom, 24)
        .appBackdrop(.today)
        .sheet(isPresented: $showingAdd) {
            AddSessionSheet(appModel: appModel)
        }
    }

    /// In overtime once presence passes the office target for the day.
    private var isOvertime: Bool {
        appModel.today.overtime(now: now) > 0
    }

    private var timeRing: some View {
        RingProgress(
            progress: appModel.today.ringProgress(now: now),
            lineWidth: 14,
            stroke: isOvertime ? AnyShapeStyle(Theme.negativeText) : nil
        )
        .frame(width: 232, height: 232)
        .overlay {
            VStack(spacing: 2) {
                Text(Keys.todayElapsed)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
                Text(Formatters.elapsed(appModel.today.presence(now: now)))
                    .font(DisplayFont.timer(46))
                    .monospacedDigit()
                    .minimumScaleFactor(0.4)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                if isOvertime {
                    Text(Keys.todayOvertime(Formatters.duration(appModel.today.overtime(now: now))))
                        .font(.footnote.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.negativeText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
                Text(Keys.todayNow(Formatters.clockWithSeconds(now)))
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 36)
        }
        .animation(.smooth, value: isOvertime)
        .frame(maxWidth: .infinity)
    }

    private var statusPill: some View {
        let today = appModel.today
        let status = today.status(now: now)
        let dotColor: Color
        let content: () -> Text
        switch status {
        case .atOffice(let since):
            dotColor = Theme.liveDot
            content = {
                Text(Keys.todayInSince(Formatters.clock(since)))
                    .foregroundStyle(.primary)
                + Text("  ·  ").foregroundStyle(Theme.tertiaryText)
                + Text(Keys.todayLeaveApprox(Formatters.clock(today.projectedFinish(now: now))))
                    .foregroundStyle(Theme.secondaryText)
            }
        case .doneForToday:
            dotColor = Theme.liveDot
            content = { Text(Keys.statusDone).foregroundStyle(.primary) }
        case .onBreak:
            dotColor = Theme.negativeText
            content = { Text(Keys.statusOnBreak).foregroundStyle(.primary) }
        case .notAtOffice:
            // Hidden before the office; unreachable.
            dotColor = Theme.secondaryText
            content = { Text(Keys.statusNotAtOffice).foregroundStyle(.primary) }
        }
        return HStack(spacing: 10) {
            Circle()
                .fill(dotColor)
                .frame(width: 8, height: 8)
                .shadow(color: dotColor, radius: 3)
            content()
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .font(.subheadline)
        .padding(.horizontal, 18)
        .padding(.vertical, 9)
        .pillSurface()
        .frame(maxWidth: .infinity)
    }

    private var statTiles: some View {
        let today = appModel.today
        return HStack(spacing: 12) {
            StatTile(
                caption: Keys.todayInOffice,
                value: Formatters.duration(today.presence(now: now))
            )
            StatTile(
                caption: Keys.worktimeTitle,
                value: Formatters.duration(today.netWorktime(now: now))
            )
            StatTile(
                caption: Keys.todayLunch,
                value: Formatters.duration(-today.settings.lunchSeconds),
                valueColor: today.settings.lunchSeconds > 0 ? Theme.negativeText : .primary
            )
        }
    }

    @ViewBuilder
    private func actionButtons() -> some View {
        if appModel.today.openSession != nil {
            Button {
                HapticsController.play(appModel.haptics.settings)
                punchTarget = .init(kind: .breakOut, now: now)
            } label: {
                Label(Keys.buttonBreak, systemImage: "cup.and.saucer")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(Theme.brand, in: Capsule())
                    .shadow(color: Theme.accent.opacity(0.35), radius: 14, y: 6)
            }
            Button {
                HapticsController.play(appModel.haptics.settings)
                punchTarget = .init(kind: .endOfDay, now: now)
            } label: {
                Label(Keys.buttonEndOfDay, systemImage: "arrow.right.to.line")
                    .font(.headline)
                    .foregroundStyle(Theme.breakLabel)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(Theme.warm, in: Capsule())
                    .shadow(color: Theme.warmShadow.opacity(0.35), radius: 30, y: 10)
            }
        } else {
            Button {
                HapticsController.play(appModel.haptics.settings)
                punchTarget = .init(kind: .clockIn, now: now)
            } label: {
                Text(appModel.today.clockInLabel(now: now))
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 17)
                    .background(Theme.brand, in: Capsule())
                    .shadow(color: Theme.accent.opacity(0.35), radius: 14, y: 6)
            }
        }
    }
}

/// Manual session entry from the header's + button — day, start and end time,
/// so previous days can be logged too. Overnight visits roll to the next day
/// when the end time is earlier than the start time.
struct AddSessionSheet: View {
    private let calendar = Calendar.current
    let appModel: AppModel
    /// Day the picker starts on — nil (today) from the + button, or the day
    /// being edited when opened from History.
    var initialDay: Date? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var day: Date = .now
    @State private var start: Date = .now
    @State private var end: Date = .now
    @State private var expandedRow: Row?
    @State private var detent = PresentationDetent.height(Self.collapsedWheelDetent)

    /// Accordion rows — only one picker open at a time.
    private enum Row { case day, start, end }

    /// Collapsed fits the three rows; expanded adds the wheel's height.
    private static let collapsedWheelDetent: CGFloat = 300
    private static let expandedWheelDetent: CGFloat = 540

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                collapsibleRow(.day, title: Keys.pickerDay, value: dayValue) {
                    DatePicker("", selection: $day)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                }
                collapsibleRow(.start, title: Keys.pickerStart, value: timeChip(start)) {
                    DatePicker("", selection: $start, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                }
                collapsibleRow(.end, title: Keys.pickerEnd, value: timeChip(end)) {
                    DatePicker("", selection: $end, displayedComponents: .hourAndMinute)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                }
                if !valid {
                    Text(Keys.addError)
                        .font(.footnote)
                        .foregroundStyle(Theme.negativeText)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .navigationTitle(Keys.addTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Keys.commonCancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Keys.commonOk) { confirm() }
                        .disabled(!valid)
                }
            }
        }
        .presentationDetents(
            [.height(Self.collapsedWheelDetent), .height(Self.expandedWheelDetent)],
            selection: $detent
        )
        .onAppear(perform: seedTimes)
    }

    private func collapsibleRow(
        _ row: Row,
        title: String,
        value: some View,
        @ViewBuilder picker: () -> some View
    ) -> some View {
        let isExpanded = expandedRow == row
        return VStack(spacing: 6) {
            Button {
                HapticsController.play(appModel.haptics.settings)
                withAnimation(.smooth(duration: 0.3)) {
                    expandedRow = isExpanded ? nil : row
                    detent = PresentationDetent.height(
                        isExpanded
                            ? Self.collapsedWheelDetent
                            : Self.expandedWheelDetent
                    )
                }
            } label: {
                HStack(spacing: 12) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Spacer()
                    value
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.secondaryText)
                        .rotationEffect(.degrees(isExpanded ? -180 : 0))
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if isExpanded {
                picker()
            }
        }
        .padding(.horizontal, 16)
        .cardSurface(cornerRadius: 20)
    }

    // Reuses the tab title's "Today": the same word, so one key covers both.
    private var dayValue: some View {
        Text(
            calendar.isDateInToday(day)
                ? Keys.tabToday
                : Formatters.weekdayDay(day)
        )
        .font(.body.weight(.semibold))
        .foregroundStyle(.primary)
    }

    private func timeChip(_ date: Date) -> some View {
        Text(Formatters.clock(date))
            .font(.body.weight(.semibold))
            .monospacedDigit()
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .background(Theme.chipFill, in: Capsule())
    }

    private var valid: Bool { sameTime == false }

    /// Same start and end means either a mistap or a zero-length entry — invalid.
    private var sameTime: Bool {
        hourMinute(of: start) == hourMinute(of: end)
    }

    /// The picked day merged with the Start wheel's time of day.
    private var combinedStart: Date {
        combine(day: day, with: start)
    }

    /// The picked day merged with the End wheel's time of day; earlier than the
    /// start means the session crossed midnight.
    private var combinedEnd: Date {
        let end = combine(day: day, with: end)
        guard end < combinedStart else { return end }
        return calendar.date(byAdding: .day, value: 1, to: end) ?? end
    }

    private func hourMinute(of date: Date) -> (hour: Int, minute: Int) {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return (hour: components.hour ?? 0, minute: components.minute ?? 0)
    }

    private func combine(day pickedDay: Date, with wheel: Date) -> Date {
        let comps = hourMinute(of: wheel)
        var components = calendar.dateComponents([.year, .month, .day], from: pickedDay)
        components.hour = comps.hour
        components.minute = comps.minute
        return calendar.date(from: components) ?? pickedDay
    }

    private func seedTimes() {
        let seededDay = calendar.startOfDay(for: initialDay ?? .now)
        day = seededDay
        start = seededDay.addingTimeInterval(9 * 3600)
        end = seededDay.addingTimeInterval(17 * 3600)
    }

    private func confirm() {
        HapticsController.play(appModel.haptics.settings)
        Task {
            await appModel.today.add(start: combinedStart, end: combinedEnd)
            dismiss()
        }
    }
}

struct PunchTimePicker: View {
    let target: TodayView.PunchTarget
    let appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var pickerDate: Date = .now

    private var title: String {
        switch target.kind {
        case .clockIn: Keys.pickerClockIn
        case .breakOut: Keys.pickerBreakOut
        case .endOfDay: Keys.pickerEndOfDay
        }
    }

    var body: some View {
        NavigationStack {
            DatePicker("", selection: $pickerDate, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Keys.commonCancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(Keys.commonOk) { confirm() }
                    }
                }
        }
        .presentationDetents([.medium])
    }

    private func confirm() {
        HapticsController.play(appModel.haptics.settings)
        Task {
            await appModel.today.punch(target.kind, picked: pickerDate, tapTime: target.now)
            dismiss()
        }
    }
}

struct SessionSection: View {
    let now: Date
    let appModel: AppModel
    @State private var editingSession: WorkSession?
    @State private var editingEnd = false

    var body: some View {
        let sessions = appModel.today.sessions(now: now)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Keys.todaySessions)
                    .font(.title3.bold())
                Spacer()
                Text(Keys.todayEditHint)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
            }
            .padding(.horizontal, 4)

            if sessions.isEmpty {
                Text(Keys.todayEmptySessions)
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 4)
            } else {
                VStack(spacing: 8) {
                    ForEach(sessions) { session in
                        Button {
                            HapticsController.play(appModel.haptics.settings)
                            editingSession = session
                            editingEnd = false
                        } label: {
                            SessionRow(session: session, now: now)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .sheet(item: $editingSession) { session in
            SessionEditSheet(
                session: session,
                editingEnd: editingEnd,
                appModel: appModel
            )
        }
    }
}

private struct SessionRow: View {
    let session: WorkSession
    let now: Date

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(session.isOpen ? Theme.overtimeFill : Theme.accent)
                .frame(width: 9, height: 9)
                .shadow(
                    color: session.isOpen ? Theme.overtimeFill : Theme.accent,
                    radius: 3
                )
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                if session.isOpen {
                    Text(Keys.sessionActive)
                        .font(.footnote)
                        .foregroundStyle(Theme.overtimeText)
                }
            }
            Spacer()
            Text(Formatters.duration(session.duration(now: now)))
                .bold()
                .monospacedDigit()
                .foregroundStyle(.primary)
            Image(systemName: "chevron_right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .cardSurface(cornerRadius: 18)
        .contentShape(Rectangle())
    }

    private var title: String {
        session.isOpen
            ? "\(Formatters.clock(session.start)) → \(Keys.sessionNow)"
            : "\(Formatters.clock(session.start)) → \(Formatters.clock(session.end!))"
    }
}

struct SessionEditSheet: View {
    let session: WorkSession
    let editingEnd: Bool
    let appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var pickerDate: Date = .now
    @State private var pickEnd = false

    private var title: String { pickEnd ? Keys.pickerEnd : Keys.pickerStart }

    var body: some View {
        NavigationStack {
            DatePicker("", selection: $pickerDate, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .padding()
                .navigationTitle(title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Keys.sessionClose) { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(Keys.sessionDelete, role: .destructive) {
                            Task {
                                await appModel.viewModel.delete(session: session)
                                dismiss()
                            }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(Keys.commonOk) { confirm() }
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button(Keys.sessionStart(Formatters.clock(session.start))) {
                            pickEnd = false
                            seedPicker()
                        }
                        Spacer()
                        if session.end != nil {
                            Button(Keys.sessionEnd(Formatters.clock(session.end!))) {
                                pickEnd = true
                                seedPicker()
                            }
                        }
                    }
                }
        }
        .presentationDetents([.medium])
        .onAppear {
            pickEnd = editingEnd
            seedPicker()
        }
    }

    private func seedPicker() {
        let calendar = Calendar.current
        let reference = pickEnd ? session.end! : session.start
        // Base day is always the session's start day (MagniTools parity).
        let baseDay = calendar.startOfDay(for: session.start)
        let components = calendar.dateComponents([.hour, .minute], from: reference)
        pickerDate = WorktimeMath.punchDate(
            onDay: baseDay,
            hour: components.hour ?? 0,
            minute: components.minute ?? 0,
            // Edits carry the original timestamp's second through.
            second: calendar.component(.second, from: reference),
            calendar: calendar
        )
    }

    private func confirm() {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: pickerDate)
        let reference = pickEnd ? session.end! : session.start
        let date = WorktimeMath.punchDate(
            onDay: calendar.startOfDay(for: session.start),
            hour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: calendar.component(.second, from: reference),
            calendar: calendar
        )
        Task {
            if pickEnd {
                await appModel.viewModel.update(session: session, start: session.start, end: date)
            } else {
                await appModel.viewModel.update(session: session, start: date, end: session.end)
            }
            dismiss()
        }
    }
}
// MARK: - Previews
#if DEBUG
#Preview("Today — clocked in") {
    TodayView()
        .environment(previewAppModel(seed: .clockedIn))
        .preferredColorScheme(.dark)
}

#Preview("Today — clocked in, light") {
    TodayView()
        .environment(previewAppModel(seed: .clockedIn))
        .preferredColorScheme(.light)
}

#Preview("Today — idle") {
    TodayView()
        .environment(previewAppModel(seed: .empty))
        .preferredColorScheme(.dark)
}

#Preview("Sessions section") {
    SessionSection(now: .now, appModel: previewAppModel(seed: .clockedIn))
        .preferredColorScheme(.dark)
}

#Preview("Add session sheet") {
    AddSessionSheet(appModel: previewAppModel(seed: .empty))
        .preferredColorScheme(.dark)
}

#Preview("Punch time picker") {
    PunchTimePicker(
        target: .init(kind: .clockIn, now: .now),
        appModel: previewAppModel(seed: .empty)
    )
    .preferredColorScheme(.dark)
}

#Preview("Edit session sheet") {
    SessionEditSheet(
        session: WorkSession(
            id: UUID(),
            start: .now.addingTimeInterval(-3 * 3600),
            end: .now.addingTimeInterval(-2 * 3600)
        ),
        editingEnd: false,
        appModel: previewAppModel(seed: .empty)
    )
    .preferredColorScheme(.dark)
}
#endif
