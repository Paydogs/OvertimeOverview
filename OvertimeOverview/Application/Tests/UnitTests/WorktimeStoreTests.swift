//
//  WorktimeStoreTests.swift
//  OvertimeOverview
//

import Foundation
import SwiftData
import Testing
@testable import OvertimeOverview

struct WorktimeStoreTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Budapest")!
        return calendar
    }()

    /// 2026-09-23 09:12:30 local (Budapest).
    static func date(_ hour: Int, _ minute: Int, _ second: Int = 0, day: Int = 23, month: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    private func makeStore() throws -> WorktimeStore {
        WorktimeStore(modelContainer: try WorktimeStore.makeInMemoryContainer())
    }

    @Test func clockInWhileOpenIsNoop() async throws {
        let store = try makeStore()
        try await store.clockIn(at: Self.date(9, 12))
        try await store.clockIn(at: Self.date(11, 0))
        let all = try await store.allSessions()
        #expect(all.count == 1)
    }

    @Test func clockOutWhileClosedIsNoop() async throws {
        let store = try makeStore()
        try await store.clockOut(at: Self.date(9, 12))
        #expect(try await store.allSessions().isEmpty)
    }

    @Test func singleOpenSessionInvariant() async throws {
        let store = try makeStore()
        try await store.clockIn(at: Self.date(9, 12))
        let open = try await store.openSession()
        #expect(open?.isOpen == true)
        try await store.clockOut(at: Self.date(17, 30))
        #expect(try await store.openSession() == nil)
    }

    @Test func allDaysGroupsByStartDayNewestFirst() async throws {
        let store = try makeStore()
        try await store.clockIn(at: Self.date(8, 0)); try await store.clockOut(at: Self.date(9, 0))
        try await store.clockIn(at: Self.date(9, 12)); try await store.clockOut(at: Self.date(12, 45))
        try await store.clockIn(at: Self.date(13, 0)); // stays open — presence keeps growing
        let days = try await store.allDays(calendar: Self.calendar)
        #expect(days.count == 1)
        #expect(days[0].sessions.count == 3)
        #expect(days[0].sessions.map(\.start) == days[0].sessions.map(\.start).sorted())
    }

    @Test func updateMovesSessionToAnotherDay() async throws {
        let store = try makeStore()
        try await store.clockIn(at: Self.date(9, 12)); try await store.clockOut(at: Self.date(17, 0))
        let session = try await store.allSessions()[0]
        try await store.update(session: session, start: Self.date(9, 0, day: 22), end: Self.date(17, 0, day: 22))
        let days = try await store.allDays(calendar: Self.calendar)
        #expect(days.count == 1)
        #expect(Self.calendar.isDate(days[0].dayStart, inSameDayAs: Self.date(9, 0, day: 22)))
    }

    @Test func deleteRemovesSession() async throws {
        let store = try makeStore()
        try await store.clockIn(at: Self.date(9, 12)); try await store.clockOut(at: Self.date(17, 0))
        let session = try await store.allSessions()[0]
        try await store.delete(session: session)
        #expect(try await store.allSessions().isEmpty)
    }
}