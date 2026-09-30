//
//  AppModel.swift
//  OvertimeOverview
//

import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class AppModel {
    private static let logger = Logger(subsystem: "hu.paydogs.overtimeoverview", category: "app")

    let store: WorktimeStore
    let viewModel: WorktimeViewModel
    let settings = WorktimeSettings.shared
    let haptics = HapticsSettingsStore.shared
    // Screen-scoped view models: pure selectors over the shared model.
    let today: TodayViewModel
    let history: HistoryViewModel
    let preferences: SettingsViewModel

    init(inMemory: Bool = false) {
        // App Group store, or in-memory (missing entitlement, or previews/tests asking
        // for it explicitly) so the app still runs instead of crashing.
        let container = inMemory ? nil : try? WorktimeStore.makeModelContainer()
        store = WorktimeStore(modelContainer: container ?? (try! WorktimeStore.makeInMemoryContainer()))
        viewModel = WorktimeViewModel(store: store)
        today = TodayViewModel(worktime: viewModel, settings: settings)
        history = HistoryViewModel(worktime: viewModel, settings: settings)
        preferences = SettingsViewModel(worktime: viewModel, settings: settings, haptics: haptics)
        if container == nil && !inMemory {
            Self.logger.error("App Group container unavailable — running with in-memory store")
        }
    }
}
