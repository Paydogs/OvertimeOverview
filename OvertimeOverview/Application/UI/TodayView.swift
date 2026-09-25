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

    var body: some View {
        let viewModel = appModel.viewModel
        let settings = appModel.settings
        let todays = viewModel.todaysSessions(now: now)
        let presence = WorktimeMath.presence(todays, now: now)
        let target = settings.officeTarget
        let net = WorktimeMath.netWorktime(presence: presence, lunch: settings.lunchSeconds)
        let overtime = presence - target
        let open = viewModel.openSession
        let dayEnded = settings.endedToday(now: now)
        let status = WorktimeMath.status(todayPresence: presence, openSession: open, dayEnded: dayEnded)

        ScrollView {
            VStack(spacing: 28) {
                Text(Keys.todayNow(Formatters.clockWithSeconds(now)))
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)

                heroRing(presence: presence, target: target, overtime: overtime,
                         dayEnded: dayEnded, status: status, open: open)

                actionButtons(open: open, presence: presence, dayEnded: dayEnded)

                VStack(spacing: 6) {
                    Text(Keys.worktimeNet(Formatters.duration(net)))
                        .font(.title2.weight(.semibold).monospaced())
                    Text(Keys.worktimeBreakdown(
                        Formatters.duration(presence),
                        Formatters.duration(settings.lunchSeconds)
                    ))
                    .foregroundStyle(.secondary)
                }

                SessionSection(now: now, appModel: appModel)
            }
            .padding()
        }
        .midnightBackdrop()
        .navigationTitle(Keys.worktimeTitle)
    }

    private func heroRing(presence: TimeInterval, target: TimeInterval, overtime: TimeInterval,
                          dayEnded: Bool, status: WorktimeMath.TodayStatus, open: WorkSession?) -> some View {
        let progress = target > 0 ? min(1, presence / target) : 0
        return VStack(spacing: 20) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.08), lineWidth: 14)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        AngularGradient(colors: Theme.brandColors, center: .center),
                        style: StrokeStyle(lineWidth: 14, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    // Soft outer glow is what sells the ring as a light source.
                    .shadow(color: Theme.accent.opacity(0.55), radius: 14)
                    .animation(.easeInOut(duration: 0.6), value: progress)
                VStack(spacing: 4) {
                    Text(Formatters.elapsed(presence))
                        .font(.system(size: 34, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                    Text("\(Int(progress * 100))%")
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 200, height: 200)

            if WorktimeMath.showsOvertime(overtime: overtime, dayEnded: dayEnded) {
                let label = overtime > 0 ? Keys.todayOvertime : Keys.todayUndertime
                Text(label(Formatters.shortDuration(overtime)))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(overtime > 0 ? Theme.accent : Theme.undertime)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .glassPill()
            }

            Group {
                switch status {
                case .atOffice(let since):
                    Text(Keys.statusAtOffice(Formatters.clock(since)))
                case .doneForToday:
                    Text(Keys.statusDone)
                case .onBreak:
                    Text(Keys.statusOnBreak)
                case .notAtOffice:
                    Text(Keys.statusNotAtOffice)
                }
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .glassPill()

            if let open, open.isOpen {
                let finish = WorktimeMath.projectedFinish(now: now, presence: presence, target: target)
                let text = finish <= now
                    ? Keys.finishFinished(Formatters.clock(finish))
                    : Keys.finishFinishes(Formatters.clock(finish))
                Text(text)
                    .font(.footnote.monospaced())
                    .foregroundStyle(.tertiary)
            }

            Text(Keys.todayProgress(
                Int(progress * 100),
                Formatters.duration(target)
            ))
            .font(.caption)
            .foregroundStyle(.tertiary)
        }
    }

    private func actionButtons(open: WorkSession?, presence: TimeInterval, dayEnded: Bool) -> some View {
        VStack(spacing: 12) {
            if open != nil {
                Button {
                    HapticsController.play(appModel.haptics.settings)
                    punchTarget = .init(kind: .breakOut, now: now)
                } label: {
                    Text(Keys.buttonBreak)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(Theme.warm, in: Capsule())
                        .shadow(color: Theme.accent.opacity(0.35), radius: 10, y: 4)
                }
                Button {
                    HapticsController.play(appModel.haptics.settings)
                    punchTarget = .init(kind: .endOfDay, now: now)
                } label: {
                    Text(Keys.buttonEndOfDay)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .glassCapsule()
                }
            } else {
                Button {
                    HapticsController.play(appModel.haptics.settings)
                    punchTarget = .init(kind: .clockIn, now: now)
                } label: {
                    Text(WorktimeMath.clockInLabel(todayPresence: presence, dayEnded: dayEnded)
                         ? Keys.buttonClockBackIn : Keys.buttonClockIn)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(Theme.brand, in: Capsule())
                        .shadow(color: Theme.accent.opacity(0.45), radius: 12, y: 4)
                }
            }
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
        VStack(alignment: .leading, spacing: 8) {
            if sessions.isEmpty {
                Text(Keys.todayEmptySessions)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
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
        HStack {
            Text(session.isOpen
                 ? "\(Formatters.clock(session.start)) – \(Keys.sessionNow)"
                 : "\(Formatters.clock(session.start)) – \(Formatters.clock(session.end!))"
            )
            .monospacedDigit()
            Spacer()
            Text(Formatters.duration(session.duration(now: now)))
                .bold()
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassCard(cornerRadius: 18)
        .contentShape(Rectangle())
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