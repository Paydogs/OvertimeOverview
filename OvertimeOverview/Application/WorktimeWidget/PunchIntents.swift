//
//  PunchIntents.swift
//  WorktimeWidget
//

import AppIntents
import Foundation
import WidgetKit

struct ClockInIntent: AppIntent {
    static var title: LocalizedStringResource = "widget_clockIn"

    func perform() async throws -> some IntentResult {
        guard let container = try? WorktimeStore.makeModelContainer() else {
            return .result()
        }
        let store = WorktimeStore(modelContainer: container)
        try? await store.clockIn(at: Date())
        await MainActor.run { WorktimeSettings.shared.clearEnded() }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct ClockOutIntent: AppIntent {
    static var title: LocalizedStringResource = "widget_clockOut"

    func perform() async throws -> some IntentResult {
        guard let container = try? WorktimeStore.makeModelContainer() else {
            return .result()
        }
        let store = WorktimeStore(modelContainer: container)
        try? await store.clockOut(at: Date())
        // Widget clock-out always marks the day ended (MagniTools asymmetry).
        await MainActor.run { WorktimeSettings.shared.markEndedToday() }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}