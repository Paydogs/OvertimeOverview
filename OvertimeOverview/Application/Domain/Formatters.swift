//
//  Formatters.swift
//  OvertimeOverview
//

import Foundation

/// Display formatting. Cached formatters are used only from the main thread
/// (DateFormatter is not Sendable); elapsed() is pure arithmetic.
enum Formatters {
    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let clockWithSecondsFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter
    }()

    private static let weekdayDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE, MMM d")
        return formatter
    }()

    private static let longWeekdayDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE, MMM d")
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEEE")
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let exportStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm"
        return formatter
    }()

    static func clock(_ date: Date) -> String { clockFormatter.string(from: date) }
    static func clockWithSeconds(_ date: Date) -> String { clockWithSecondsFormatter.string(from: date) }
    static func month(_ date: Date) -> String { monthFormatter.string(from: date) }
    static func weekdayDay(_ date: Date) -> String { weekdayDayFormatter.string(from: date) }
    static func longWeekdayDay(_ date: Date) -> String { longWeekdayDayFormatter.string(from: date) }
    static func weekday(_ date: Date) -> String { weekdayFormatter.string(from: date) }
    static func dateTime(_ date: Date) -> String { dateTimeFormatter.string(from: date) }
    static func exportStamp(_ date: Date) -> String { exportStampFormatter.string(from: date) }

    /// Live elapsed duration, e.g. "7:32:10". Truncates to whole seconds.
    static func elapsed(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval))
        return String(format: "%d:%02d:%02d", totalSeconds / 3600, (totalSeconds % 3600) / 60, totalSeconds % 60)
    }

    /// Whole-minute duration, e.g. "7h 32m", minus-prefixed when negative
    /// (U+2212, not a hyphen — the handoff tokens demand the typographic minus).
    /// Deviation from the brief: the generated Keys accessors are parameterized
    /// functions (Keys.formatHoursMinutes(_:_:_)), not format strings.
    static func duration(_ interval: TimeInterval) -> String {
        let sign = interval < 0 ? "−" : ""
        let totalMinutes = Int(abs(interval) / 60)
        return sign + Keys.formatHoursMinutes(totalMinutes / 60, totalMinutes % 60)
    }

    /// Under an hour → localized whole minutes ("25 min"); otherwise `duration`.
    static func shortDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(abs(interval) / 60)
        guard minutes < 60 else { return duration(interval) }
        let sign = interval < 0 ? "−" : ""
        return sign + Keys.formatMinutes(minutes)
    }
}