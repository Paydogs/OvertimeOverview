//
//  WorkSession.swift
//  OvertimeOverview
//

import Foundation

/// A single office visit. `end` is nil while it's still in progress.
struct WorkSession: Identifiable, Equatable, Sendable {
    let id: UUID
    let start: Date
    let end: Date?

    var isOpen: Bool { end == nil }
    func duration(now: Date) -> TimeInterval { (end ?? now).timeIntervalSince(start) }
}

/// A calendar day with the time segments that belong to it. A session belongs to
/// the day it started in, even if it spans midnight.
struct WorkDay: Identifiable, Equatable, Sendable {
    let dayStart: Date
    let sessions: [WorkSession]

    var id: Date { dayStart }
    func inOffice(now: Date) -> TimeInterval { sessions.reduce(0) { $0 + $1.duration(now: now) } }
}