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

    init() {
        let container = try? WorktimeStore.makeModelContainer()
        // App Group store, or in-memory fallback (missing entitlement) so the
        // app still runs instead of crashing.
        store = WorktimeStore(modelContainer: container ?? (try! WorktimeStore.makeInMemoryContainer()))
        viewModel = WorktimeViewModel(store: store)
        if container == nil {
            Self.logger.error("App Group container unavailable — running with in-memory store")
        }
    }
}