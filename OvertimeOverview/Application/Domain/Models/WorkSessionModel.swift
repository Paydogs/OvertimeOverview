//
//  WorkSessionModel.swift
//  OvertimeOverview
//

import Foundation
import SwiftData

@Model
final class WorkSessionModel {
    @Attribute(.unique) var id: UUID
    var start: Date
    var end: Date?

    init(id: UUID = UUID(), start: Date, end: Date? = nil) {
        self.id = id
        self.start = start
        self.end = end
    }
}