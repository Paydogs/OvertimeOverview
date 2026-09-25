//
//  WorktimeSettingsTests.swift
//  OvertimeOverview
//

import Foundation
import Testing
@testable import OvertimeOverview

@MainActor
struct WorktimeSettingsTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Budapest")!
        return calendar
    }()

    private func makeSettings() -> WorktimeSettings {
        let name = "WorktimeSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return WorktimeSettings(defaults: defaults)
    }

    @Test func defaults() {
        let settings = makeSettings()
        #expect(settings.workSeconds == 8 * 3600)
        #expect(settings.lunchSeconds == 30 * 60)
        #expect(settings.officeTarget == 8 * 3600 + 30 * 60)
    }

    @Test func updateWholeMinutes() {
        let settings = makeSettings()
        settings.updateWork(minutes: 90)
        #expect(settings.workSeconds == 5400)
    }

    // Review Focus 4: a marker set yesterday must not count as ended today.
    @Test func endedMarkerFromYesterdayIsNotEndedToday() {
        let settings = makeSettings()
        let yesterday = Self.calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 23, hour: 18)
        )!
        let today = Self.calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 24, hour: 9)
        )!
        settings.markEndedToday(now: yesterday, calendar: Self.calendar)
        #expect(settings.endedToday(now: today, calendar: Self.calendar) == false)
        #expect(settings.endedToday(now: yesterday, calendar: Self.calendar) == true)
    }

    @Test func clearEnded() {
        let settings = makeSettings()
        settings.markEndedToday(calendar: Self.calendar)
        settings.clearEnded()
        #expect(settings.endedToday(calendar: Self.calendar) == false)
    }
}