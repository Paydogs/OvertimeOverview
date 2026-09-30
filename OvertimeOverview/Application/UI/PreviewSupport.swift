//
//  PreviewSupport.swift
//  OvertimeOverview
//

#if DEBUG
import SwiftUI

/// What a preview's in-memory store should contain.
enum PreviewSeed {
    case empty
    /// A finished morning session plus the still-open one.
    case clockedIn
    /// Two past workdays for the history list.
    case history
}

/// In-memory AppModel for #Previews — never touches the App Group store.
/// Seeding hops through the store actor, so it lands shortly after the first
/// render and updates the @Observable view model in place.
@MainActor
func previewAppModel(seed: PreviewSeed = .empty) -> AppModel {
    let model = AppModel(inMemory: true)
    let now = Date.now
    let calendar = Calendar.current
    let sessions: [(start: Date, end: Date?)] = switch seed {
    case .empty:
        []
    case .clockedIn:
        [
            (now.addingTimeInterval(-5 * 3600), now.addingTimeInterval(-4 * 3600)),
            (now.addingTimeInterval(-3 * 3600), nil),
        ]
    case .history:
        // Two sessions per past weekday, 09:00–13:30 and 14:00–18:00.
        (1...14).compactMap { offset in
            let day = calendar.date(byAdding: .day, value: -offset, to: now)!
            guard !calendar.isDateInWeekend(day) else { return nil }
            let dayStart = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
            return (dayStart, dayStart.addingTimeInterval(9 * 3600))
        }
    }

    if !sessions.isEmpty {
        Task {
            for session in sessions {
                try? await model.store.insertSession(start: session.start, end: session.end)
            }
            await model.viewModel.refresh()
        }
    }
    return model
}
#endif