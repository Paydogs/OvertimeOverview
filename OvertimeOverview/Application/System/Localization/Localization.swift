//
//  Localization.swift
//  OvertimeOverview
//
//  Created by Andras Olah on 2026. 09. 25..
//

import Foundation

public enum LanguageCode: String {
    case en
    case hu

    var localizedValue: String {
        switch self {
        case .en: Keys.languageCodeEn
        case .hu: Keys.languageCodeHu
        }
    }
}

/// Sync, lock-protected localization: the generated `Keys.tr` is nonisolated and
/// synchronous, so this cannot be an actor — every mutable state access is
/// guarded by `lock`, which makes the class data-race-free.
public final class Localization: @unchecked Sendable {
    public static let sharedInstance = Localization()

    // MARK: - Privates
    private static let languageKey = "savedLanguage"
    private let bundle: Bundle
    private let lock = NSLock()
    private var _currentLanguageCode: LanguageCode

    // MARK: - Init
    init(
        bundle: Bundle = .module,
        deviceLanguage: String? = Locale.current.language.languageCode?.identifier,
        defaults: UserDefaults = .standard
    ) {
        self.bundle = bundle
        if let storedLanguage = defaults.string(forKey: Self.languageKey),
           let languageCode = LanguageCode(rawValue: storedLanguage) {
            _currentLanguageCode = languageCode
        } else {
            // Locale.current.identifier is e.g. "hu_HU@calendar=…" and never matches
            // a bare raw value; `language.languageCode` is the bare "hu" / "en".
            let languageCode = LanguageCode(rawValue: deviceLanguage ?? "") ?? .en
            defaults.set(languageCode.rawValue, forKey: Self.languageKey)
            _currentLanguageCode = languageCode
        }
    }
}

public extension Localization {
    var currentLanguageCode: LanguageCode {
        lock.withLock { _currentLanguageCode }
    }

    func setLanguage(_ code: LanguageCode) {
        lock.withLock { _currentLanguageCode = code }
        UserDefaults.standard.set(code.rawValue, forKey: Self.languageKey)
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
    }

    /// Resolve localized string manually
    func translate(_ key: String, _ table: String) -> String {
        let code = lock.withLock { _currentLanguageCode }
        // Missing keys resolve from the base-language (en) sub-bundle, not the
        // main bundle: the main bundle follows the device's system-preferred
        // localization, so on a device set to a third language an en-only key
        // would still surface as the raw key instead of the English string.
        guard let basePath = bundle.path(forResource: LanguageCode.en.rawValue, ofType: "lproj"),
              let baseBundle = Bundle(path: basePath)
        else { return bundle.localizedString(forKey: key, value: nil, table: table) }

        let fallback = baseBundle.localizedString(forKey: key, value: nil, table: table)
        guard let path = bundle.path(forResource: code.rawValue, ofType: "lproj"),
              let localizedBundle = Bundle(path: path)
        else { return fallback }

        // A miss in the selected-language lproj falls back to the base-language
        // string resolved above.
        return localizedBundle.localizedString(forKey: key, value: fallback, table: table)
    }
}

public extension Notification.Name {
    static let languageDidChange = Notification.Name("Localization.languageDidChange")
}