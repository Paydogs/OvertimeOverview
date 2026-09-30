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

    init(inMemory: Bool = false) {
        // App Group store, or in-memory (missing entitlement, or previews/tests asking
        // for it explicitly) so the app still runs instead of crashing.
        let container = inMemory ? nil : try? WorktimeStore.makeModelContainer()
        store = WorktimeStore(modelContainer: container ?? (try! WorktimeStore.makeInMemoryContainer()))
        viewModel = WorktimeViewModel(store: store)
        if container == nil && !inMemory {
            Self.logger.error("App Group container unavailable — running with in-memory store")
        }
    }
}