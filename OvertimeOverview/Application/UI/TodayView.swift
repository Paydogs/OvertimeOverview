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
        enum Kind { case clockIn, breakOut, endOfDay }
        let kind: Kind
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
        let viewModel = appModel.viewModel
        let settings = appModel.settings
        let todays = viewModel.todaysSessions(now: now)
        let presence = WorktimeMath.presence(todays, now: now)
        let target = settings.officeTarget
        let net = WorktimeMath.netWorktime(presence: presence, lunch: settings.lunchSeconds)
        let open = viewModel.openSession
        let dayEnded = settings.endedToday(now: now)
        let status = WorktimeMath.status(todayPresence: presence, openSession: open, dayEnded: dayEnded)

        ScrollView {
            VStack(spacing: 22) {
                ScreenHeader(title: Keys.tabToday, caption: Formatters.longWeekdayDay(now)) {
                    RoundIconButton(systemImage: "plus") {
                        HapticsController.play(appModel.haptics.settings)
                        showingAdd = true
                    }
                }

                heroTimer(presence: presence, target: target, open: open)

                statusPill(status: status, presence: presence, target: target)

                statTiles(presence: presence, net: net, lunch: settings.lunchSeconds)

                SessionSection(now: now, appModel: appModel)

                actionButtons(open: open, presence: presence, dayEnded: dayEnded)
            }
            .padding(.horizontal, 16)
        }
        .appBackdrop()
        .sheet(isPresented: $showingAdd) {
            AddSessionSheet(appModel: appModel)
        }
    }

    /// Circular day-progress ring; the elapsed time lives in its center.
    private func heroTimer(presence: TimeInterval, target: TimeInterval, open: WorkSession?) -> some View {
        let progress = target > 0 ? presence / target : 0
        return RingProgress(progress: progress)
            .frame(width: 288, height: 288)
            .overlay {
                VStack(spacing: 6) {
                    Text(Keys.todayElapsed)
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                    Text(Formatters.elapsed(presence))
                        .font(DisplayFont.timer(46))
                        .monospacedDigit()
                        .minimumScaleFactor(0.4)
                        .lineLimit(1)
                        .foregroundStyle(.primary)
                    Text(Keys.todayNow(Formatters.clockWithSeconds(now)))
                        .font(.callout)
                        .foregroundStyle(Theme.secondaryText)
                }
                .padding(.horizontal, 40)
            }
            .frame(maxWidth: .infinity)
    }

    private func statusPill(
        status: WorktimeMath.TodayStatus,
        presence: TimeInterval,
        target: TimeInterval
    ) -> some View {
        // When not at the office yet this is "if you clocked in now" — still a useful anchor.
        let finish = WorktimeMath.projectedFinish(now: now, presence: presence, target: target)
        let dotColor: Color
        let content: Text
        switch status {
        case .atOffice(let since):
            dotColor = Theme.dotGreen
            content = Text(Keys.todayInSince(Formatters.clock(since))) + Text("  ·  ") + Text(Keys.todayLeaveApprox(Formatters.clock(finish)))
        case .doneForToday:
            dotColor = Theme.dotGreen
            content = Text(Keys.statusDone)
        case .onBreak:
            dotColor = Theme.undertime
            content = Text(Keys.statusOnBreak)
        case .notAtOffice:
            dotColor = Theme.secondaryText
            content = Text(Keys.statusNotAtOffice)
        }
        return HStack(spacing: 10) {
            Circle().fill(dotColor).frame(width: 9, height: 9)
            content
                .monospacedDigit()
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .font(.subheadline)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .pillSurface()
        .frame(maxWidth: .infinity)
    }

    private func statTiles(presence: TimeInterval, net: TimeInterval, lunch: TimeInterval) -> some View {
        HStack(spacing: 12) {
            StatTile(caption: Keys.worktimeTitle, value: Formatters.duration(net))
            StatTile(caption: Keys.todayInOffice, value: Formatters.duration(presence))
            StatTile(
                caption: Keys.todayLunch,
                value: Formatters.duration(-lunch),
                valueColor: lunch > 0 ? Theme.undertime : .primary
            )
        }
    }

    private func actionButtons(open: WorkSession?, presence: TimeInterval, dayEnded: Bool) -> some View {
        VStack(spacing: 14) {
            if open != nil {
                Button {
                    HapticsController.play(appModel.haptics.settings)
                    punchTarget = .init(kind: .breakOut, now: now)
                } label: {
                    Label(Keys.buttonBreak, systemImage: "cup.and.saucer")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(Theme.warm, in: Capsule())
                        .shadow(color: Theme.warmShadow.opacity(0.45), radius: 14, y: 6)
                }
                Button {
                    HapticsController.play(appModel.haptics.settings)
                    punchTarget = .init(kind: .endOfDay, now: now)
                } label: {
                    Label(Keys.buttonEndOfDay, systemImage: "arrow.right.to.line")
                        .font(.headline)
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .capsuleSurface()
                }
            } else {
                Button {
                    HapticsController.play(appModel.haptics.settings)
                    punchTarget = .init(kind: .clockIn, now: now)
                } label: {
                    Text(WorktimeMath.clockInLabel(todayPresence: presence, dayEnded: dayEnded)
                         ? Keys.buttonClockBackIn : Keys.buttonClockIn)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 17)
                        .background(Theme.brand, in: Capsule())
                        .shadow(color: Theme.accent.opacity(0.45), radius: 14, y: 6)
                }
            }
        }
    }
}

/// Manual session entry from the header's + button.
struct AddSessionSheet: View {
    let appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var start: Date = .now
    @State private var end: Date = .now

    var body: some View {
        NavigationStack {
            List {
                DatePicker(Keys.pickerStart, selection: $start, displayedComponents: .hourAndMinute)
                DatePicker(Keys.pickerEnd, selection: $end, displayedComponents: .hourAndMinute)
                if !valid {
                    Text(Keys.addError)
                        .font(.footnote)
                        .foregroundStyle(Theme.undertime)
                }
            }
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
        .presentationDetents([.medium])
        .onAppear(perform: seedTimes)
    }

    private var valid: Bool { end > start }

    private func seedTimes() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: .now)
        start = day.addingTimeInterval(9 * 3600)
        end = day.addingTimeInterval(17 * 3600)
    }

    private func confirm() {
        HapticsController.play(appModel.haptics.settings)
        Task {
            await appModel.viewModel.add(start: start, end: end)
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
            DatePicker(title, selection: $pickerDate, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .padding()
                .navigationTitle(Keys.worktimeTitle)
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
        let calendar = Calendar.current
        // Clock-out uses the open session's start day as the base day
        // (MagniTools parity: a session can be closed on the day it started).
        let baseDay: Date
        if target.kind == .clockIn {
            baseDay = calendar.startOfDay(for: target.now)
        } else {
            baseDay = calendar.startOfDay(for: appModel.viewModel.openSession?.start ?? target.now)
        }
        let components = calendar.dateComponents([.hour, .minute], from: pickerDate)
        let date = WorktimeMath.punchDate(
            onDay: baseDay,
            hour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: calendar.component(.second, from: target.now),
            calendar: calendar
        )

        Task {
            let viewModel = appModel.viewModel
            let settings = appModel.settings
            switch target.kind {
            case .clockIn:
                await viewModel.clockIn(at: date)
                settings.clearEnded()
            case .breakOut:
                await viewModel.clockOut(at: date)
                settings.clearEnded()
            case .endOfDay:
                await viewModel.clockOut(at: date)
                settings.markEndedToday()
            }
            HapticsController.play(appModel.haptics.settings)
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
        let sessions = appModel.viewModel.todaysSessions(now: now)
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(Keys.todaySessions)
                    .font(.title2.bold())
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
                .fill(session.isOpen ? Theme.overtime : Theme.accent)
                .frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .monospacedDigit()
                    .foregroundStyle(.primary)
                if session.isOpen {
                    Text(Keys.sessionActive)
                        .font(.footnote)
                        .foregroundStyle(Theme.overtime)
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

private struct SessionEditSheet: View {
    let session: WorkSession
    let editingEnd: Bool
    let appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var pickerDate: Date = .now
    @State private var pickEnd = false

    private var title: String { pickEnd ? Keys.pickerEnd : Keys.pickerStart }

    var body: some View {
        NavigationStack {
            DatePicker(title, selection: $pickerDate, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .padding()
                .navigationTitle(Keys.sessionEdit)
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