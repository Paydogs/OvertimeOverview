//
//  Theme.swift
//  OvertimeOverview
//
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// App-wide palette, matching worktime-redesign-handoff/ios/design-tokens.json.
/// Every semantic color is adaptive, so the same views render both appearances.
enum Theme {
    #if canImport(UIKit)
    private static func adaptive(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
    #endif

    private static func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    static let primaryText = adaptive(rgb(0x14112A), .white)
    static let secondaryText = adaptive(rgb(0x5E5B6E), rgb(0xEBEBF5, alpha: 0.60))
    static let tertiaryText = adaptive(rgb(0x3C3C43, alpha: 0.35), rgb(0xEBEBF5, alpha: 0.35))

    // Backdrop: navy → plum in dark; lavender wash in light.
    static let bgTop = adaptive(rgb(0xF6F5FB), rgb(0x090D20))
    static let bgMid = adaptive(rgb(0xEFEBF9), rgb(0x140F2C))
    static let bgBottom = adaptive(rgb(0xEAE4F7), rgb(0x190F30))
    static let backgroundGlow = adaptive(
        rgb(0x8954E7, alpha: 0.16),
        rgb(0x8954E7, alpha: 0.28)
    )
    static let settingsGlow = adaptive(
        rgb(0x0A84FF, alpha: 0.12),
        rgb(0x0A84FF, alpha: 0.18)
    )

    // Card surfaces.
    static let surface = adaptive(
        rgb(0xFFFFFF, alpha: 0.72),
        rgb(0xFFFFFF, alpha: 0.07)
    )
    static let surfaceStroke = adaptive(
        rgb(0xFFFFFF, alpha: 0.95),
        rgb(0xFFFFFF, alpha: 0.10)
    )
    static let surfaceShadow = adaptive(
        rgb(0x28145A, alpha: 0.07),
        rgb(0x000000, alpha: 0.25)
    )
    static let separator = adaptive(rgb(0x14112A, alpha: 0.08), rgb(0xFFFFFF, alpha: 0.08))

    static let accent = adaptive(rgb(0x0071E3), rgb(0x0A84FF))
    static let accentFill = adaptive(rgb(0x0071E3, alpha: 0.10), rgb(0x0A84FF, alpha: 0.16))

    static let overtimeText = adaptive(rgb(0x7A3FE0), rgb(0xB48CFF))
    static let overtimeFill = Color(rgb: 0x8954E7)
    static let negativeText = adaptive(rgb(0xC4501E), rgb(0xFF8D54))
    static let liveDot = adaptive(rgb(0x28B44C), rgb(0x30D158))

    // Ring.
    static let ringTrack = adaptive(rgb(0x14112A, alpha: 0.07), rgb(0xFFFFFF, alpha: 0.08))

    // Break (clock out for a break) button; the label is dark on coral because
    // white fails contrast (handoff tokens: onBreak #2A0A0E).
    static let breakLabel = Color(rgb: 0x2A0A0E)
    static let warm = LinearGradient(
        colors: [Color(rgb: 0xFF6C69), Color(rgb: 0xFF8D54)],
        startPoint: .leading, endPoint: .trailing
    )
    static let warmShadow = Color(rgb: 0xFF6C69)

    // Clock-in button.
    static let brand = LinearGradient(
        colors: [adaptive(rgb(0x2A94FF), rgb(0x2E99FF)),
                 adaptive(rgb(0x0059CB), rgb(0x0A6FE0))],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // History month summary card.
    static let monthGradient = LinearGradient(
        colors: [adaptive(rgb(0xEDE6FB), rgb(0x6B51CF)),
                 adaptive(rgb(0xF6F3FC), rgb(0x2A1B4D))],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let monthText = primaryText
    static let monthTextSecondary = secondaryText
    static let monthOvertime = overtimeText

    // Icon tiles (Settings rows) and small chips (History day badge).
    static let tileBlue = Color(rgb: 0x0A84FF)
    static let tileOrange = Color(rgb: 0xFF8D54)
    static let tilePurple = Color(rgb: 0x8954E7)
    static let tileGreen = adaptive(rgb(0x34C759), rgb(0x30D158))
    static let tileGray = adaptive(rgb(0x8E8E93), rgb(0x636366))
    static let chipFill = adaptive(
        rgb(0x000000, alpha: 0.05),
        rgb(0xFFFFFF, alpha: 0.08)
    )
    static let chipOvertimeFill = adaptive(
        rgb(0x8954E7, alpha: 0.12),
        rgb(0x8954E7, alpha: 0.22)
    )
}

enum BackdropStyle {
    case today, history, settings
}

// MARK: - Surfaces

extension View {
    /// Standard content card, adaptive for both color schemes.
    func cardSurface(cornerRadius: CGFloat = 22) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.surface)
                .shadow(color: Theme.surfaceShadow, radius: 18, y: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.surfaceStroke, lineWidth: 1)
        }
    }

    /// Elevated card (hero ring area); slightly brighter fill in dark mode.
    func heroSurface(cornerRadius: CGFloat = 28) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.chipFill)
                .shadow(color: Theme.surfaceShadow, radius: 18, y: 8)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.surfaceStroke, lineWidth: 1)
        }
    }

    /// History's month summary card.
    func monthSurface(cornerRadius: CGFloat = 30) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.monthGradient)
                .shadow(color: Theme.surfaceShadow, radius: 24, y: 10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.surfaceStroke, lineWidth: 1)
        }
    }

    /// Floating capsule surface for secondary buttons.
    func capsuleSurface() -> some View {
        background {
            Capsule()
                .fill(Theme.surface)
                .shadow(color: Theme.surfaceShadow, radius: 18, y: 8)
        }
        .overlay {
            Capsule().strokeBorder(Theme.surfaceStroke, lineWidth: 1)
        }
    }

    /// Small pill status bubble.
    func pillSurface() -> some View {
        background {
            Capsule().fill(Theme.surface)
        }
        .overlay {
            Capsule().strokeBorder(Theme.surfaceStroke, lineWidth: 1)
        }
    }

    /// Full-screen adaptive backdrop with the per-screen radial glow.
    func appBackdrop(_ style: BackdropStyle = .today) -> some View {
        background {
            ZStack {
                LinearGradient(
                    colors: [Theme.bgTop, Theme.bgMid, Theme.bgBottom],
                    startPoint: .top, endPoint: .bottom
                )
                RadialGradient(
                    colors: [glow(style), .clear],
                    center: glowCenter(style),
                    startRadius: 0,
                    endRadius: 420
                )
            }
            .ignoresSafeArea()
        }
    }

    private func glow(_ style: BackdropStyle) -> Color {
        switch style {
        case .today: Theme.backgroundGlow
        case .history: Theme.backgroundGlow
        case .settings: Theme.settingsGlow
        }
    }

    private func glowCenter(_ style: BackdropStyle) -> UnitPoint {
        switch style {
        case .today: UnitPoint(x: 0.5, y: 0.3)
        case .history: UnitPoint(x: 0.8, y: 0.12)
        case .settings: UnitPoint(x: 0.15, y: 0.10)
        }
    }
}

// MARK: - Display font

/// Bricolage Grotesque (variable font, registered via UIAppFonts). iOS exposes its
/// weight instances under a style-suffixed PostScript name, so a weight must be
/// resolved explicitly — `.weight()` on the family leaves the lookup to the system.
/// Falls back to SF Pro Rounded when the font is missing.
enum DisplayFont {
    private static let available: Bool = {
        #if canImport(UIKit)
        !UIFont.fontNames(forFamilyName: "Bricolage Grotesque").isEmpty
        #else
        false
        #endif
    }()

    /// The hero timer on the Today screen.
    static func timer(_ size: CGFloat = 56, weight: Font.Weight = .bold) -> Font {
        guard available else {
            return .system(size: size, weight: weight, design: .rounded)
        }
        return .custom(instanceName(for: weight), fixedSize: size)
    }

    /// Instance names as registered by CoreText (verified via `UIFont.fontNames(forFamilyName:)`).
    private static func instanceName(for weight: Font.Weight) -> String {
        let style: String
        switch weight {
        case .ultraLight, .thin: style = "ExtraLight"
        case .light: style = "Light"
        case .medium: style = "Medium"
        case .semibold: style = "SemiBold"
        case .bold: style = "Bold"
        case .heavy, .black: style = "ExtraBold"
        default: style = "Regular"
        }
        return "BricolageGrotesque-96ptExtraBold_" + style
    }
}