//
//  WorktimeViewModelTests.swift
//  OvertimeOverview
//

import Foundation
import SwiftData
import Testing
@testable import OvertimeOverview

@MainActor
struct WorktimeViewModelTests {
    private func makeViewModel() throws -> WorktimeViewModel {
        WorktimeViewModel(store: WorktimeStore(modelContainer: try WorktimeStore.makeInMemoryContainer()))
    }

    @Test func refreshLoadsDays() async throws {
        let viewModel = try makeViewModel()
        let calendar = Calendar.current
        await viewModel.clockIn(at: calendar.startOfDay(for: Date()).addingTimeInterval(3600))
        #expect(viewModel.days.count == 1)
        #expect(viewModel.openSession?.isOpen == true)
    }

    @Test func importBackupReplacesAndMerges() async throws {
        let viewModel = try makeViewModel()
        let name = "VMBackupTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = WorktimeSettings(defaults: defaults)
        let json = """
        { "app": "OvertimeOverview", "version": 3, "exportedAt": "2026-01-01 00:00:00",
          "worktime": [ { "start": 1000000, "end": 2000000 } ] }
        """
        // Merge into empty store
        let merged = await viewModel.importBackup(data: Data(json.utf8), replace: false, settings: settings)
        #expect(merged == 1)
        // Replace wipes the 1 existing, inserts 1
        let replaced = await viewModel.importBackup(data: Data(json.utf8), replace: true, settings: settings)
        #expect(replaced == 1)
        #expect(viewModel.days.flatMap(\.sessions).count == 1)
    }
}