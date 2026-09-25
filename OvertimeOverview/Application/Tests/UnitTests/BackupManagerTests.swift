//
//  BackupManagerTests.swift
//  OvertimeOverview
//

import Foundation
import Testing
@testable import OvertimeOverview

struct BackupManagerTests {
    private static let budapest = TimeZone(identifier: "Europe/Budapest")!

    /// A real MagniTools v3 export: dotted keys, millis timestamps, legacy top-level "sessions" absent.
    private static let magnitoolsJSON = """
    {
      "app": "MagniTools",
      "version": 3,
      "exportedAt": "2026-06-05 14:30:00",
      "settings": { "workMillis": 28800000, "lunchMillis": 1800000, "endedDayStart": 0 },
      "worktime": [
        { "start": 1748179200000, "end": 1748208000000,
          "startText": "2026-05-25 10:00:00", "endText": "2026-05-25 18:00:00" },
        { "start": 1748445600000, "end": null,
          "startText": "2026-05-28 12:00:00", "endText": null }
      ]
    }
    """

    @Test func parsesMagnitoolsV3() throws {
        let parsed = try BackupManager.parse(Data(Self.magnitoolsJSON.utf8))
        #expect(parsed.sessions.count == 2)
        #expect(parsed.sessions[0].start == Date(timeIntervalSince1970: 1_748_179_200))
        #expect(parsed.sessions[1].end == nil)
        #expect(parsed.settings?.workMillis == 28_800_000)
    }

    @Test func parsesLegacyTopLevelSessions() throws {
        let legacy = """
        { "app": "MagniTools", "version": 1, "exportedAt": "2026-01-01 09:00:00",
          "sessions": [ { "start": 1748179200000, "end": 1748208000000 } ] }
        """
        let parsed = try BackupManager.parse(Data(legacy.utf8))
        #expect(parsed.sessions.count == 1)
    }

    @Test func roundTrip() throws {
        let session = WorkSession(id: UUID(), start: Date(timeIntervalSince1970: 1_000), end: nil)
        let document = BackupManager.makeDocument(
            sessions: [session],
            settings: BackupSettingsDTO(workMillis: 28_800_000, lunchMillis: 1_800_000, endedDayStart: nil),
            now: Date(timeIntervalSince1970: 100)
        )
        let data = try BackupManager.encode(document)
        let parsed = try BackupManager.parse(data)
        #expect(parsed.sessions.count == 1)
        #expect(parsed.sessions[0].start == session.start)
        #expect(parsed.sessions[0].end == nil)
    }

    // Review Focus 5: merge appends without dedup; replace wipes first.
    // These exercise the store operations BackupManager's callers perform;
    // they live here to keep the backup contract in one place.
    @Test func mergeAppendAndReplaceWipe() async throws {
        let store = WorktimeStore(modelContainer: try WorktimeStore.makeInMemoryContainer())
        try await store.insertSession(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 10))
        let parsed = try BackupManager.parse(Data(Self.magnitoolsJSON.utf8))
        // Replace: wipe, then insert all
        try await store.deleteAllSessions()
        for session in parsed.sessions { try await store.insertSession(start: session.start, end: session.end) }
        #expect(try await store.allSessions().count == 2)
        // Merge: append without dedup — the same import again doubles the rows
        for session in parsed.sessions { try await store.insertSession(start: session.start, end: session.end) }
        #expect(try await store.allSessions().count == 4)
    }
}