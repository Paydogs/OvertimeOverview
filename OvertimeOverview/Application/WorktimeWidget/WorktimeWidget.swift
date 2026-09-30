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
}

struct WorktimeStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: .now, statusText: NSLocalizedString("widget_notClockedIn", comment: ""), isWorking: false)
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
            return StatusEntry(date: now, statusText: NSLocalizedString("widget_notClockedIn", comment: ""), isWorking: false)
        }
        let store = WorktimeStore(modelContainer: container)
        let endedToday = await MainActor.run { WorktimeSettings.shared.endedToday(now: now) }
        // try? does not double-wrap optionals (SE-0230), so a single binding suffices.
        if let open = try? await store.openSession() {
            return StatusEntry(
                date: now,
                statusText: String(
                    format: NSLocalizedString("widget_inSince", comment: ""),
                    Formatters.clock(open.start)
                ),
                isWorking: true
            )
        }
        if endedToday {
            return StatusEntry(date: now, statusText: NSLocalizedString("widget_done", comment: ""), isWorking: false)
        }
        return StatusEntry(date: now, statusText: NSLocalizedString("widget_notClockedIn", comment: ""), isWorking: false)
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

    /// The likely next action gets the gradient fill; the other one sits in glass.
    private func punchLabel(icon: String, prominent: Bool, gradient: LinearGradient) -> some View {
        Image(systemName: icon)
            .font(.body.weight(.semibold))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .foregroundStyle(.white)
            .background(
                prominent ? AnyShapeStyle(gradient) : AnyShapeStyle(.ultraThinMaterial),
                in: Capsule()
            )
            .overlay(Capsule().strokeBorder(Color.white.opacity(prominent ? 0 : 0.15), lineWidth: 1))
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