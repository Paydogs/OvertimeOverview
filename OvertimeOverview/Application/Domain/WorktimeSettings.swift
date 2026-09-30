//
//  WorktimeSettings.swift
//  OvertimeOverview
//

import Foundation
import Observation

/// workSeconds is the work you owe; lunchSeconds is added on top for the
/// presence target and deducted from presence for net worktime.
/// endedDayStart marks a day finished (break vs. clocking out for good).
@MainActor
@Observable
final class WorktimeSettings {
    static let shared = WorktimeSettings()

    static let workKey = "work_seconds"
    static let lunchKey = "lunch_seconds"
    static let endedKey = "ended_day_start"
    /// iCloud sync preference — flipped in Settings, applied on next launch.
    static let iCloudSyncKey = "icloud_sync_enabled"
    static let defaultWork: TimeInterval = 8 * 3600
    static let defaultLunch: TimeInterval = 30 * 60

    private let defaults: UserDefaults
    private(set) var workSeconds: TimeInterval
    private(set) var lunchSeconds: TimeInterval
    private(set) var endedDayStart: Date?
    private(set) var iCloudSyncEnabled: Bool

    var officeTarget: TimeInterval { workSeconds + lunchSeconds }

    init(defaults: UserDefaults = UserDefaults(suiteName: WorktimeStore.appGroup) ?? .standard) {
        self.defaults = defaults
        workSeconds = defaults.object(forKey: Self.workKey) as? Double ?? Self.defaultWork
        lunchSeconds = defaults.object(forKey: Self.lunchKey) as? Double ?? Self.defaultLunch
        endedDayStart = defaults.object(forKey: Self.endedKey) as? Date
        iCloudSyncEnabled = defaults.bool(forKey: Self.iCloudSyncKey)
    }

    func updateWork(minutes: Int) {
        workSeconds = Double(minutes) * 60
        defaults.set(workSeconds, forKey: Self.workKey)
    }

    func updateLunch(minutes: Int) {
        lunchSeconds = Double(minutes) * 60
        defaults.set(lunchSeconds, forKey: Self.lunchKey)
    }

    /// Marks today as finished ("Clock out for today" / widget clock-out).
    func markEndedToday(now: Date = Date(), calendar: Calendar = .current) {
        endedDayStart = calendar.startOfDay(for: now)
        defaults.set(endedDayStart, forKey: Self.endedKey)
    }

    /// Clears the end-of-day marker (clock-in, break clock-out).
    func clearEnded() {
        endedDayStart = nil
        defaults.removeObject(forKey: Self.endedKey)
    }

    /// Records the sync preference; the store picks it up at next launch.
    func setSyncEnabled(_ newValue: Bool) {
        iCloudSyncEnabled = newValue
        defaults.set(newValue, forKey: Self.iCloudSyncKey)
    }

    func endedToday(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let ended = endedDayStart else { return false }
        return calendar.startOfDay(for: ended) == calendar.startOfDay(for: now)
    }

    /// Restores all settings at once (backup import).
    func importState(work: TimeInterval, lunch: TimeInterval, endedDayStart: Date?) {
        workSeconds = work
        lunchSeconds = lunch
        self.endedDayStart = endedDayStart
        defaults.set(work, forKey: Self.workKey)
        defaults.set(lunch, forKey: Self.lunchKey)
        defaults.set(endedDayStart, forKey: Self.endedKey)
    }
}