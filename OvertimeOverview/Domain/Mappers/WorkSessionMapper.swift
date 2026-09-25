//
//  WorkSessionMapper.swift
//  OvertimeOverview
//

import Foundation

/// The only place that maps between persistence and domain models.
enum WorkSessionMapper {
    static func toDomain(_ model: WorkSessionModel) -> WorkSession {
        WorkSession(id: model.id, start: model.start, end: model.end)
    }

    static func apply(_ session: WorkSession, to model: WorkSessionModel) {
        model.start = session.start
        model.end = session.end
    }
}