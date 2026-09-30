//
//  WorkSessionModel.swift
//  OvertimeOverview
//

import Foundation
import SwiftData

/// One office visit. CloudKit-compatible: no unique attributes, every property
/// optional or defaulted (SwiftData's iCloud sync refuses anything else).
@Model
final class WorkSessionModel {
    var id: UUID = UUID()
    var start: Date = Date()
    var end: Date?

    init(id: UUID = UUID(), start: Date, end: Date? = nil) {
        self.id = id
        self.start = start
        self.end = end
    }
}