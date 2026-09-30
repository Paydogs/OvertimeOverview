//
//  BackupSessionMapper.swift
//  OvertimeOverview
//

import Foundation

/// MagniTools-compatible backup document. Timestamps are epoch milliseconds.
struct BackupSessionDTO: Codable {
    let start: Int64
    let end: Int64?
    let startText: String?
    let endText: String?
}

struct BackupSettingsDTO: Codable {
    var workMillis: Int64?
    var lunchMillis: Int64?
    var endedDayStart: Int64?
}

struct BackupDocument: Codable {
    let app: String
    let version: Int
    let exportedAt: String
    var settings: BackupSettingsDTO?
    var worktime: [BackupSessionDTO]?
    /// Legacy MagniTools key, accepted on import only.
    var sessions: [BackupSessionDTO]?
}

enum BackupManager {
    static let formatVersion = 3

    struct ParsedBackup {
        let sessions: [(start: Date, end: Date?)]
        let settings: BackupSettingsDTO?
    }

    static func parse(_ data: Data) throws -> ParsedBackup {
        let document = try JSONDecoder().decode(BackupDocument.self, from: data)
        let entries = document.worktime ?? document.sessions ?? []
        return ParsedBackup(
            sessions: entries.map {
                (start: Date(timeIntervalSince1970: Double($0.start) / 1000),
                 end: $0.end.map { Date(timeIntervalSince1970: Double($0) / 1000) })
            },
            settings: document.settings
        )
    }

    static func makeDocument(sessions: [WorkSession], settings: BackupSettingsDTO, now: Date) -> BackupDocument {
        BackupDocument(
            app: "OvertimeOverview",
            version: formatVersion,
            exportedAt: Formatters.dateTime(now),
            settings: settings,
            worktime: sessions.map { session in
                BackupSessionDTO(
                    start: Int64(session.start.timeIntervalSince1970 * 1000),
                    end: session.end.map { Int64($0.timeIntervalSince1970 * 1000) },
                    startText: Formatters.dateTime(session.start),
                    endText: session.end.map(Formatters.dateTime)
                )
            },
            sessions: nil
        )
    }

    static func encode(_ document: BackupDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }
}