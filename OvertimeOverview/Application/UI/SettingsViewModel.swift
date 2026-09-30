//
//  SettingsViewModel.swift
//  OvertimeOverview
//

import Foundation
import UniformTypeIdentifiers
import Observation

/// Settings screen state: the backup flow (export / import confirmation /
/// alerts) and the haptics-config actions. Exports open the system location
/// picker bound to `shareURL`; the alert is view-level plumbing.
@MainActor
@Observable
final class SettingsViewModel {
    private let worktime: WorktimeViewModel
    let settings: WorktimeSettings
    let haptics: HapticsSettingsStore

    init(worktime: WorktimeViewModel, settings: WorktimeSettings, haptics: HapticsSettingsStore) {
        self.worktime = worktime
        self.settings = settings
        self.haptics = haptics
    }

    // MARK: - State for the view

    private(set) var alertMessage: String?
    private(set) var shareURL: URL?

    /// Non-nil while the "replace or merge?" dialog is up.
    private(set) var pendingImport: Data?

    /// Identifiable wrapper so `.sheet(item:)` can present the share URL.
    struct ShareItem: Identifiable {
        let url: URL
        var id: String { url.absoluteString }
    }

    var shareItem: ShareItem? {
        shareURL.map(ShareItem.init)
    }

    func dismissAlert() { alertMessage = nil }
    func cancelImport() { pendingImport = nil }
    func dismissShare() { shareURL = nil }

    // MARK: - Backup flow

    /// Writes the backup to a temp file; on failure falls back to an alert.
    func exportBackup() {
        guard let data = worktime.exportBackup(settings: settings),
              let url = try? Self.writeTempJSON(data)
        else {
            alertMessage = Keys.backupExportFailed
            return
        }
        shareURL = url
    }

    private static func writeTempJSON(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("overtimeoverview-\(Formatters.exportStamp(Date())).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    // MARK: - Excel export

    /// Builds the .xlsx from every session; open ones export without End/Elapsed
    /// until closed. Shares through the same sheet as the JSON backup.
    func exportExcel() {
        do {
            let sessions = worktime.days.flatMap(\.sessions)
            let data = try ExcelExporter.makeWorkbook(sessions: sessions, calendar: .current)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("overtimeoverview-\(Formatters.exportStamp(Date())).xlsx")
            try data.write(to: url, options: .atomic)
            shareURL = url
        } catch {
            alertMessage = Keys.backupExportFailed
        }
    }

    /// Reads an imported file (security-scoped); asks replace-or-merge in the dialog.
    func readImport(at url: URL) {
        guard url.startAccessingSecurityScopedResource(),
              let data = try? Data(contentsOf: url)
        else {
            alertMessage = Keys.backupFailed
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        pendingImport = data
    }

    func importBackup(replace: Bool) {
        guard let data = pendingImport else { return }
        pendingImport = nil
        Task {
            if let count = await worktime.importBackup(
                data: data, replace: replace, settings: settings
            ) {
                alertMessage = Keys.backupImported(count)
            } else {
                alertMessage = Keys.backupFailed
            }
        }
    }

    // MARK: - Haptics config

    /// iCloud sync preference: the store reads it at launch, so the change
    /// needs a relaunch (the subtitle under the toggle says so).
    func setSyncEnabled(_ newValue: Bool) {
        settings.setSyncEnabled(newValue)
    }

    func setHapticsEnabled(_ newValue: Bool) {
        var settings = haptics.settings
        settings.enabled = newValue
        haptics.update(settings)
        if newValue { HapticsController.play(settings) }
    }

    func setHapticStrength(_ newValue: Double) {
        var settings = haptics.settings
        settings.strength = newValue
        haptics.update(settings)
    }

    func setHapticPattern(_ newValue: HapticPattern) {
        var settings = haptics.settings
        settings.pattern = newValue
        haptics.update(settings)
    }

    func testHaptics() {
        HapticsController.play(haptics.settings)
    }

    // MARK: - Labels

    func hapticPatternLabel(_ pattern: HapticPattern) -> String {
        switch pattern {
        case .single: Keys.hapticSingle
        case .double: Keys.hapticDouble
        case .triple: Keys.hapticTriple
        case .long: Keys.hapticLong
        }
    }
}