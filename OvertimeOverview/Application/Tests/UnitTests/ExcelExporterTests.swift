//
//  ExcelExporterTests.swift
//  OvertimeOverview
//

import Foundation
import Testing
@testable import OvertimeOverview

struct ExcelExporterTests {
    private static let calendar = Calendar.current

    private static func date(_ hour: Int, _ minute: Int, day: Int = 2, month: Int = 9) -> Date {
        var components = DateComponents()
        components.year = 2026
        components.month = month
        components.day = day
        components.hour = hour
        components.minute = minute
        return calendar.date(from: components)!
    }

    @Test func packageIsAStoredZip() throws {
        let workbook = try ExcelExporter.makeWorkbook(
            sessions: [WorkSession(id: UUID(), start: Self.date(9, 0), end: Self.date(17, 0))],
            calendar: Self.calendar
        )
        // Local file header PK\3\4 opens the archive; the EOCD record (PK\5\6,
        // 22 bytes incl. comment length) closes it.
        #expect(Array(workbook.prefix(4)) == [0x50, 0x4B, 0x03, 0x04])
        #expect(workbook.count >= 22)
        #expect(
            Array(workbook.suffix(22).prefix(4)) == [0x50, 0x4B, 0x05, 0x06]
        )
    }

    @Test func sheetCarriesHeaderAndSessionRows() throws {
        let workbook = try ExcelExporter.makeWorkbook(
            sessions: [
                WorkSession(id: UUID(), start: Self.date(9, 15), end: Self.date(17, 45)),
                WorkSession(id: UUID(), start: Self.date(20, 0), end: Self.date(21, 30)),
            ],
            calendar: Self.calendar
        )
        // Entries are stored uncompressed, so the sheet text is literal in the zip.
        let text = String(decoding: workbook, as: UTF8.self)
        #expect(text.contains("Dátum") || text.contains("Date"))
        #expect(text.contains("2026-09-02"))
        // Both session rows exist: the same date block repeats with its own times.
        #expect(text.components(separatedBy: "2026-09-02").count >= 3)
    }

    @Test func elapsedIsEndMinusStart() throws {
        let workbook = try ExcelExporter.makeWorkbook(
            sessions: [WorkSession(id: UUID(), start: Self.date(9, 0), end: Self.date(17, 0))],
            calendar: Self.calendar
        )
        let text = String(decoding: workbook, as: UTF8.self)
        // 8h elapsed = 8/24 of a day, as an [h]:mm day fraction.
        #expect(text.contains("0.3333"))
    }

    @Test func openSessionExportsWithoutEndAndElapsed() throws {
        let workbook = try ExcelExporter.makeWorkbook(
            sessions: [WorkSession(id: UUID(), start: Self.date(8, 30), end: nil)],
            calendar: Self.calendar
        )
        let text = String(decoding: workbook, as: UTF8.self)
        #expect(text.contains("2026-09-02"))
        // No elapsed cell (style s=\"2\", the [h]:mm format) for the open row.
        #expect(!text.contains("s=\"2\""))
    }
}