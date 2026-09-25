//
//  LocalizationTests.swift
//  OvertimeOverview
//

import Foundation
import Testing
@testable import OvertimeOverview

@MainActor
struct LocalizationTests {
    private func makeDefaults() -> UserDefaults {
        let name = "LocalizationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func detectsHungarianFromLocale() {
        let defaults = makeDefaults()
        let localization = Localization(
            bundle: Bundle(for: AppDelegate.self),
            deviceLanguage: "hu",
            defaults: defaults
        )
        #expect(localization.currentLanguageCode == .hu)
        #expect(defaults.string(forKey: "savedLanguage") == "hu")
    }

    @Test func unknownLocaleFallsBackToEnglish() {
        let localization = Localization(
            bundle: Bundle(for: AppDelegate.self),
            deviceLanguage: "de",
            defaults: makeDefaults()
        )
        #expect(localization.currentLanguageCode == .en)
    }

    @Test func storedLanguageWins() {
        let defaults = makeDefaults()
        defaults.set("hu", forKey: "savedLanguage")
        let localization = Localization(
            bundle: Bundle(for: AppDelegate.self),
            deviceLanguage: "en",
            defaults: defaults
        )
        #expect(localization.currentLanguageCode == .hu)
    }

    @Test func missingKeyFallsBackToBaseLanguage() {
        let defaults = makeDefaults()
        let localization = Localization(
            bundle: Bundle(for: AppDelegate.self),
            deviceLanguage: "hu",
            defaults: defaults
        )
        // "test_englishOnly" exists in en.lproj only (added below)
        #expect(localization.translate("test_englishOnly", "Localizable") == "English only string")
        // A key present in both languages resolves from the selected (hu) lproj
        #expect(localization.translate("language_code_en", "Localizable") == "Angol")
        // A key missing everywhere still surfaces the raw key
        #expect(localization.translate("no.such.key", "Localizable") == "no.such.key")
    }
}