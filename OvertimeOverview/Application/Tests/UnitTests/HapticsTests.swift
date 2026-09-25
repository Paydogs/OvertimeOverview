//
//  HapticsTests.swift
//  OvertimeOverview
//

import Foundation
import Testing
@testable import OvertimeOverview

@MainActor
struct HapticsTests {
    @Test func patternTimings() {
        #expect(HapticPattern.single.bursts == [45])
        #expect(HapticPattern.long.bursts == [180])
        #expect(HapticPattern.double.bursts == [45, 45] && HapticPattern.double.pauses == [60])
        #expect(HapticPattern.triple.bursts == [40, 40, 40] && HapticPattern.triple.pauses == [55, 55])
    }

    @Test func settingsPersist() {
        let name = "HapticsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let store = HapticsSettingsStore(defaults: defaults)
        #expect(store.settings.enabled && store.settings.strength == 0.7)
        store.update(HapticSettings(enabled: false, strength: 0.4, pattern: .long))
        let reloaded = HapticsSettingsStore(defaults: defaults)
        #expect(reloaded.settings.enabled == false)
        #expect(reloaded.settings.strength == 0.4)
        #expect(reloaded.settings.pattern == .long)
    }
}