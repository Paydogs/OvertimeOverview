//
//  WorktimeViewModel.swift
//  OvertimeOverview
//

import Foundation
import Observation

@MainActor
@Observable
final class WorktimeViewModel {
    private let store: WorktimeStore

    /// All days with their sessions, newest day first.
    private(set) var days: [WorkDay] = []

    var openSession: WorkSession? {
        days.flatMap(\.sessions).last { $0.isOpen }
    }

    init(store: WorktimeStore) {
        self.store = store
    }

    func refresh() async {
        days = (try? await store.allDays(calendar: .current)) ?? []
    }

    func clockIn(at date: Date) async {
        try? await store.clockIn(at: date)
        await refresh()
    }

    func clockOut(at date: Date) async {
        try? await store.clockOut(at: date)
        await refresh()
    }

    func update(session: WorkSession, start: Date, end: Date?) async {
        try? await store.update(session: session, start: start, end: end)
        await refresh()
    }

    func delete(session: WorkSession) async {
        try? await store.delete(session: session)
        await refresh()
    }

    /// Sessions that started today, newest first.
    func todaysSessions(now: Date = Date()) -> [WorkSession] {
        WorktimeMath.todaysSessions(days.flatMap(\.sessions), now: now, calendar: .current)
    }

    /// Number of imported sessions, nil when the document couldn't be parsed.
    func importBackup(data: Data, replace: Bool, settings: WorktimeSettings) async -> Int? {
        guard let parsed = try? BackupManager.parse(data) else { return nil }
        if replace {
            try? await store.deleteAllSessions()
        }
        for session in parsed.sessions {
            try? await store.insertSession(start: session.start, end: session.end)
        }
        if let imported = parsed.settings {
            settings.importState(
                work: imported.workMillis.map { Double($0) / 1000 } ?? settings.workSeconds,
                lunch: imported.lunchMillis.map { Double($0) / 1000 } ?? settings.lunchSeconds,
                endedDayStart: imported.endedDayStart
                    .flatMap { $0 == 0 ? nil : $0 }
                    .map { Date(timeIntervalSince1970: Double($0) / 1000) }
            )
        }
        await refresh()
        return parsed.sessions.count
    }

    func exportBackup(settings: WorktimeSettings, now: Date = Date()) -> Data? {
        let document = BackupManager.makeDocument(
            sessions: days.flatMap(\.sessions),
            settings: BackupSettingsDTO(
                workMillis: Int64(settings.workSeconds * 1000),
                lunchMillis: Int64(settings.lunchSeconds * 1000),
                endedDayStart: settings.endedDayStart.map { Int64($0.timeIntervalSince1970 * 1000) }
            ),
            now: now
        )
        return try? BackupManager.encode(document)
    }
}