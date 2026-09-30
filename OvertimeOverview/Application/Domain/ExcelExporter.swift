//
//  ExcelExporter.swift
//  OvertimeOverview
//

import Foundation

/// Builds a minimal .xlsx (OpenXML spreadsheet) from the session list for the
/// Settings "Export as Excel" row: one row per session, chronological, header
/// row bold. Times are written as day fractions with Excel time formats, so
/// the Elapsed column is literally end − start and stays formula-friendly in
/// the sheet tool. The zip container uses stored (uncompressed) entries — no
/// third-party zip dependency.
enum ExcelExporter {
    static func makeWorkbook(sessions: [WorkSession], calendar: Calendar) throws -> Data {
        let entries = [
            Entry(
                name: "[Content_Types].xml",
                data: Data(Self.contentTypesXML.utf8)
            ),
            Entry(name: "_rels/.rels", data: Data(Self.rootRelsXML.utf8)),
            Entry(name: "xl/workbook.xml", data: Data(Self.workbookXML.utf8)),
            Entry(name: "xl/_rels/workbook.xml.rels", data: Data(Self.workbookRelsXML.utf8)),
            Entry(name: "xl/styles.xml", data: Data(Self.stylesXML.utf8)),
            Entry(name: "xl/worksheets/sheet1.xml", data: Data(try Self.sheet1XML(sessions: sessions, calendar: calendar).utf8)),
        ]
        return Self.zipArchive(entries: entries)
    }

    // MARK: - Package parts

    private struct Entry {
        let name: String
        let data: Data
    }

    private static let contentTypesXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>
        <Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>
        </Types>
        """

    private static let rootRelsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>
        </Relationships>
        """

    private static let workbookXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        <sheets><sheet name="Sessions" sheetId="1" r:id="rId1"/></sheets>
        </workbook>
        """

    private static let workbookRelsXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
        <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>
        <Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
        </Relationships>
        """

    /// Custom number formats: s1 = wall-clock h:mm, s2 = elapsed [h]:mm so
    /// overnight and long sessions show 25:30 instead of wrapping at 24.
    private static let stylesXML = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <numFmts count="2">
        <numFmt numFmtId="164" formatCode="h:mm"/>
        <numFmt numFmtId="165" formatCode="[h]:mm"/>
        </numFmts>
        <fonts count="2">
        <font><sz val="11"/><name val="Calibri"/></font>
        <font><b/><sz val="11"/><name val="Calibri"/></font>
        </fonts>
        <fills count="2">
        <fill><patternFill patternType="none"/></fill>
        <fill><patternFill patternType="gray125"/></fill>
        </fills>
        <borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>
        <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
        <cellXfs count="4">
        <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>
        <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
        <xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>
        <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>
        </cellXfs>
        </styleSheet>
        """

    private static func sheet1XML(sessions: [WorkSession], calendar: Calendar) throws -> String {
        let columns = [
            Keys.excelDate,
            Keys.excelStart,
            Keys.excelEnd,
            Keys.excelElapsed,
        ]
        var rows = [Self.headerRow(columns)]
        // Sessions may arrive newest-first; the sheet reads chronologically.
        for session in sessions.sorted(by: { $0.start < $1.start }) {
            let date = Self.dateFormatter.string(from: session.start)
            var cells = [
                "<c r=\"A\(rows.count + 1)\" t=\"inlineStr\"><is><t>\(Self.escaped(date))</t></is></c>",
                "<c r=\"B\(rows.count + 1)\" s=\"1\"><v>\(Self.dayFraction(session.start, calendar: calendar))</v></c>",
            ]
            if let end = session.end {
                // Elapsed = end − start, as a day fraction ([h]:mm shows >24h).
                let seconds = end.timeIntervalSince(session.start)
                cells.append("<c r=\"C\(rows.count + 1)\" s=\"1\"><v>\(Self.dayFraction(end, calendar: calendar))</v></c>")
                cells.append("<c r=\"D\(rows.count + 1)\" s=\"2\"><v>\(seconds / 86_400)</v></c>")
            }
            // Open sessions export with empty End/Elapsed until they are closed.
            rows.append("<row r=\"\(rows.count + 1)\">\(cells.joined())</row>")
        }
        return """
            <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
            <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
            <cols>
            <col min="1" max="1" width="12" customWidth="1"/>
            <col min="2" max="3" width="10" customWidth="1"/>
            <col min="4" max="4" width="10" customWidth="1"/>
            </cols>
            <sheetData>
            \(rows.joined(separator: "\n"))
            </sheetData>
            </worksheet>
            """
    }

    private static func headerRow(_ columns: [String]) -> String {
        let letters = ["A", "B", "C", "D"]
        let cells = zip(letters, columns.prefix(letters.count)).map { letter, text in
            "<c r=\"\(letter)1\" t=\"inlineStr\" s=\"3\"><is><t>\(Self.escaped(text))</t></is></c>"
        }
        return "<row r=\"1\">\(cells.joined())</row>"
    }

    /// h:mm:ss fraction of the day — Excel renders day fractions as times.
    private static func dayFraction(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        let seconds = Double(components.hour ?? 0) * 3_600
            + Double(components.minute ?? 0) * 60
            + Double(components.second ?? 0)
        return "\(seconds / 86_400)"
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static func escaped(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    // MARK: - Zip container (stored entries)

    private static func zipArchive(entries: [Entry]) -> Data {
        var output = Data()
        var centralDirectory = Data()
        var offset: UInt32 = 0

        for entry in entries {
            let name = Data(entry.name.utf8)
            let crc = Self.crc32(entry.data)
            let size = UInt32(entry.data.count)

            let localHeader = Self.bytes(localHeaderSignature)
                + Self.bytes(UInt16(20))            // version to extract
                + Self.bytes(UInt16(0))             // flags
                + Self.bytes(UInt16(0))             // method: stored
                + Self.bytes(UInt16(0))             // DOS time
                + Self.bytes(UInt16(0))             // DOS date
                + Self.bytes(crc)
                + Self.bytes(size) + Self.bytes(size)
                + Self.bytes(UInt16(name.count)) + Self.bytes(UInt16(0))
            let startOffset = offset
            output += Data(localHeader) + name + entry.data

            let centralHeader = Self.bytes(centralHeaderSignature)
                + Self.bytes(UInt16(20))            // version made by
                + Self.bytes(UInt16(20))            // version to extract
                + Self.bytes(UInt16(0))             // flags
                + Self.bytes(UInt16(0))             // method: stored
                + Self.bytes(UInt16(0)) + Self.bytes(UInt16(0))  // time, date
                + Self.bytes(crc)
                + Self.bytes(size) + Self.bytes(size)
                + Self.bytes(UInt16(name.count)) + Self.bytes(UInt16(0))  // name, extra len
                + Self.bytes(UInt16(0)) + Self.bytes(UInt16(0))           // comment, disk
                + Self.bytes(UInt16(0))             // internal attrs
                + Self.bytes(UInt32(0))             // external attrs
                + Self.bytes(startOffset)
            centralDirectory += Data(centralHeader) + name

            offset += UInt32(localHeader.count + name.count + entry.data.count)
        }

        output += centralDirectory
        output += Data(
            Self.bytes(eocdSignature)
                + Self.bytes(UInt16(0)) + Self.bytes(UInt16(0))  // disk numbers
                + Self.bytes(UInt16(entries.count)) + Self.bytes(UInt16(entries.count))
                + Self.bytes(UInt32(centralDirectory.count))
                + Self.bytes(offset)
                + Self.bytes(UInt16(0))             // comment length
        )
        return output
    }

    private static let eocdSignature: UInt32 = 0x06054B50
    private static let localHeaderSignature: UInt32 = 0x04034B50
    private static let centralHeaderSignature: UInt32 = 0x02014B50

    private static func bytes(_ value: UInt32) -> [UInt8] {
        (0..<4).map { UInt8((value >> ($0 * 8)) & 0xFF) }
    }

    private static func bytes(_ value: UInt16) -> [UInt8] {
        (0..<2).map { UInt8((value >> ($0 * 8)) & 0xFF) }
    }

    // MARK: - CRC32

    private static let crc32Table: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) == 1 ? 0xEDB88320 ^ (value >> 1) : value >> 1
            }
            return value
        }
    }()

    private static func crc32(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = (crc >> 8) ^ crc32Table[Int((crc ^ UInt32(byte)) & 0xFF)]
        }
        return crc ^ 0xFFFF_FFFF
    }
}