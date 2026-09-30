//
//  WorktimeWidget.swift
//  WorktimeWidget
//

import SwiftUI
import WidgetKit

struct StatusEntry: TimelineEntry {
    let date: Date
    let statusText: String
    let isWorking: Bool
    /// "Leave ≈ HH:mm" while the session is open; nil otherwise.
    let leaveText: String?
}

struct WorktimeStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: .now, statusText: NSLocalizedString("widget_notClockedIn", comment: ""), isWorking: false, leaveText: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        Task { completion(await currentEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        Task {
            let entry = await currentEntry()
            // Refresh hourly while inactive; punches reload immediately.
            let next = Calendar.current.date(byAdding: .hour, value: 1, to: entry.date)!
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func currentEntry() async -> StatusEntry {
        let now = Date()
        guard let container = try? WorktimeStore.makeModelContainer() else {
            return StatusEntry(date: now, statusText: NSLocalizedString("widget_notClockedIn", comment: ""), isWorking: false, leaveText: nil)
        }
        let store = WorktimeStore(modelContainer: container)
        let calendar = Calendar.current
        // WorktimeSettings.shared is @MainActor — read both values in one hop.
        let (endedToday, officeTarget) = await MainActor.run {
            (WorktimeSettings.shared.endedToday(now: now), WorktimeSettings.shared.officeTarget)
        }
        // try? does not double-wrap optionals (SE-0230), so a single binding suffices.
        if let open = try? await store.openSession() {
            // Same projection as the app's Today screen: presence so far vs. the office target.
            let sessions = (try? await store.allSessions()) ?? []
            let presence = WorktimeMath.presence(
                WorktimeMath.todaysSessions(sessions, now: now, calendar: calendar),
                now: now
            )
            let finish = WorktimeMath.projectedFinish(now: now, presence: presence, target: officeTarget)
            return StatusEntry(
                date: now,
                statusText: String(
                    format: NSLocalizedString("widget_inSince", comment: ""),
                    Formatters.clock(open.start)
                ),
                isWorking: true,
                leaveText: Keys.widgetLeave(Formatters.clock(finish))
            )
        }
        let notClockedIn = StatusEntry(
            date: now,
            statusText: NSLocalizedString(
                endedToday ? "widget_done" : "widget_notClockedIn",
                comment: ""
            ),
            isWorking: false,
            leaveText: nil
        )
        return notClockedIn
    }
}

struct WorktimeWidgetView: View {
    let entry: StatusEntry

    // Midnight glass accents, inlined — Theme.swift is compiled into the app target only.
    private let brandGradient = LinearGradient(
        colors: [Color(red: 106 / 255, green: 90 / 255, blue: 224 / 255),
                 Color(red: 166 / 255, green: 75 / 255, blue: 244 / 255)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    private let warmGradient = LinearGradient(
        colors: [Color(red: 1, green: 107 / 255, blue: 107 / 255),
                 Color(red: 1, green: 142 / 255, blue: 83 / 255)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// The likely next action shows its gradient at full strength; the other one
    /// stays on the same gradient, dimmed — both render as colors, so widget
    /// state swaps crossfade simply instead of jumping between fill kinds.
    private func punchLabel(icon: String, prominent: Bool, gradient: LinearGradient) -> some View {
        Image(systemName: icon)
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .foregroundStyle(.white)
            .background(
                AnyShapeStyle(gradient.opacity(prominent ? 1 : 0.3)),
                in: Capsule()
            )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(NSLocalizedString("widget_name", comment: ""))
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(entry.statusText)
                .font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if let leaveText = entry.leaveText {
                Text(leaveText)
                    .font(.subheadline.weight(.medium).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Button(intent: ClockInIntent()) {
                    punchLabel(icon: "arrow.right.circle.fill",
                               prominent: !entry.isWorking,
                               gradient: brandGradient)
                }
                .buttonStyle(.plain)
                Button(intent: ClockOutIntent()) {
                    punchLabel(icon: "arrow.left.circle.fill",
                               prominent: entry.isWorking,
                               gradient: warmGradient)
                }
                .buttonStyle(.plain)
            }
        }
        // The backdrop is always dark, so keep text and materials light even in system Light Mode.
        .environment(\.colorScheme, .dark)
        .containerBackground(for: .widget) {
            ZStack {
                // Matches the app's midnight backdrop.
                LinearGradient(
                    colors: [Color(red: 0.03, green: 0.05, blue: 0.12),
                             Color(red: 0.10, green: 0.06, blue: 0.19)],
                    startPoint: .top, endPoint: .bottom
                )
                // Blurred violet glow for depth.
                Circle()
                    .fill(Color(red: 166 / 255, green: 75 / 255, blue: 244 / 255))
                    .blur(radius: 50)
                    .opacity(0.35)
                    .frame(width: 160, height: 160)
                    .offset(x: 70, y: -60)
            }
        }
    }
}

struct WorktimeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WorktimeWidget", provider: WorktimeStatusProvider()) { entry in
            WorktimeWidgetView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("widget_name", comment: ""))
        .description(NSLocalizedString("widget_description", comment: ""))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}