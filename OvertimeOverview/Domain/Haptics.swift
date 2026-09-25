//
//  Haptics.swift
//  OvertimeOverview
//

import CoreHaptics
import Foundation
import Observation

enum HapticPattern: String, CaseIterable, Codable {
    case single, double, triple, long

    /// Transient burst durations in ms (MagniTools timings).
    var bursts: [UInt] {
        switch self {
        case .single: [45]
        case .long: [180]
        case .double: [45, 45]
        case .triple: [40, 40, 40]
        }
    }

    /// Pauses between bursts in ms.
    var pauses: [UInt] {
        switch self {
        case .single, .long: []
        case .double: [60]
        case .triple: [55, 55]
        }
    }
}

struct HapticSettings: Codable {
    var enabled = true
    var strength = 0.7
    var pattern: HapticPattern = .single
}

@MainActor
@Observable
final class HapticsSettingsStore {
    static let shared = HapticsSettingsStore()
    private static let key = "haptic_settings"

    private let defaults: UserDefaults
    private(set) var settings: HapticSettings

    init(defaults: UserDefaults = UserDefaults(suiteName: WorktimeStore.appGroup) ?? .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(HapticSettings.self, from: data) {
            settings = decoded
        } else {
            settings = HapticSettings()
        }
    }

    func update(_ newSettings: HapticSettings) {
        settings = newSettings
        if let data = try? JSONEncoder().encode(newSettings) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

@MainActor
enum HapticsController {
    private static let engine = try? CHHapticEngine()

    static func play(_ settings: HapticSettings) {
        guard settings.enabled,
              CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine
        else { return }

        let intensity = CHHapticEventParameter(
            parameterID: .hapticIntensity, value: Float(settings.strength)
        )
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1)
        var events: [CHHapticEvent] = []
        var time: TimeInterval = 0
        for (index, burst) in settings.pattern.bursts.enumerated() {
            events.append(
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [intensity, sharpness],
                    relativeTime: time
                )
            )
            if index < settings.pattern.pauses.count {
                time += Double(burst) / 1000 + Double(settings.pattern.pauses[index]) / 1000
            }
        }
        guard let pattern = try? CHHapticPattern(events: events, parameters: []),
              let player = try? engine.makePlayer(with: pattern)
        else { return }
        try? engine.start()
        try? player.start(atTime: 0)
    }
}