//
//  WorktimeStore.swift
//  OvertimeOverview
//

import Foundation
import SwiftData

@ModelActor
actor WorktimeStore {
    nonisolated static let appGroup = "group.hu.paydogs.overtimeoverview"

    nonisolated static func makeModelContainer() throws -> ModelContainer {
        // App Group when the entitlement is present, otherwise a plain local store
        // (unit tests, previews).
        guard let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) else {
            return try ModelContainer(for: WorkSessionModel.self)
        }
        let storeURL = groupURL.appendingPathComponent("worktime.sqlite")
        // iCloud sync is a user preference read at store creation; flipping it
        // needs a relaunch, so failures here fall back to plain local sync.
        let cloudKit: ModelConfiguration.CloudKitDatabase? = isCloudSyncEnabled(
            defaults: UserDefaults(suiteName: appGroup) ?? .standard
        )
            ? .private(iCloudContainerID)
            : .none

        if let container = try? ModelContainer(for: WorkSessionModel.self, configurations: cloudKit.map {
            ModelConfiguration(url: storeURL, cloudKitDatabase: $0)
        } ?? ModelConfiguration(url: storeURL)) {
            return container
        }
        // Missing or mismatched iCloud entitlement (simulator, CI) — retry locally
        // instead of dropping to in-memory, which would lose all sessions.
        return try ModelContainer(
            for: WorkSessionModel.self,
            configurations: ModelConfiguration(url: storeURL, cloudKitDatabase: .none)
        )
    }

    /// The iCloud container this app syncs sessions to.
    nonisolated static let iCloudContainerID = "iCloud.hu.paydogs.overtime"

    /// Whether the store syncs sessions via iCloud — reads the synced-settings
    /// preference from the App Group defaults.
    nonisolated static func isCloudSyncEnabled(defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: WorktimeSettings.iCloudSyncKey)
    }

    nonisolated static func makeInMemoryContainer() throws -> ModelContainer {
        // Explicitly opt out: automatic discovery would pick up the iCloud
        // entitlement and demand CloudKit's schema rules from this store too.
        try ModelContainer(
            for: WorkSessionModel.self,
            configurations: ModelConfiguration(
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
        )
    }

    private func openSessionModel() throws -> WorkSessionModel? {
        var descriptor = FetchDescriptor<WorkSessionModel>(predicate: #Predicate { $0.end == nil })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func openSession() throws -> WorkSession? {
        try openSessionModel().map(WorkSessionMapper.toDomain)
    }

    func clockIn(at date: Date) throws {
        guard try openSessionModel() == nil else { return }
        modelContext.insert(WorkSessionModel(start: date, end: nil))
        try modelContext.save()
    }

    func clockOut(at date: Date) throws {
        guard let open = try openSessionModel() else { return }
        open.end = date
        try modelContext.save()
    }

    func update(session: WorkSession, start: Date, end: Date?) throws {
        let id = session.id
        guard let model = try modelContext.fetch(
            FetchDescriptor<WorkSessionModel>(predicate: #Predicate { $0.id == id })
        ).first else { return }
        WorkSessionMapper.apply(WorkSession(id: id, start: start, end: end), to: model)
        try modelContext.save()
    }

    func delete(session: WorkSession) throws {
        let id = session.id
        guard let model = try modelContext.fetch(
            FetchDescriptor<WorkSessionModel>(predicate: #Predicate { $0.id == id })
        ).first else { return }
        modelContext.delete(model)
        try modelContext.save()
    }

    func deleteAllSessions() throws {
        try modelContext.delete(model: WorkSessionModel.self)
        try modelContext.save()
    }

    func insertSession(start: Date, end: Date?) throws {
        modelContext.insert(WorkSessionModel(start: start, end: end))
        try modelContext.save()
    }

    func allSessions() throws -> [WorkSession] {
        try modelContext.fetch(
            FetchDescriptor<WorkSessionModel>(sortBy: [SortDescriptor(\.start)])
        ).map(WorkSessionMapper.toDomain)
    }

    /// All days newest first, sessions chronological within a day. Day grouping
    /// is derived from each session's start — never stored, never split at midnight.
    func allDays(calendar: Calendar) throws -> [WorkDay] {
        WorktimeMath.groupSessions(try allSessions(), calendar: calendar)
    }
}