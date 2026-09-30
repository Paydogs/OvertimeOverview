//
//  Theme.swift
//  OvertimeOverview
//
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// App-wide palette. Every semantic color is adaptive, so the same views render
/// both the midnight design (dark) and its light companion without separate layouts.
enum Theme {
    private static func adaptive(_ light: UIColor, _ dark: UIColor) -> Color {
        Color(UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }

    private static func rgb(_ hex: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    static let white = adaptive(
        .init(red: 1, green: 1, blue: 1, alpha: 1),
        .init(red: 1, green: 1, blue: 1, alpha: 1)
    )
    static let black = adaptive(
        .init(red: 0.11, green: 0.11, blue: 0.16, alpha: 1),
        .init(red: 1, green: 1, blue: 1, alpha: 1)
    )
    static let secondaryText = adaptive(
        .init(red: 0.42, green: 0.40, blue: 0.48, alpha: 1),
        .init(red: 1, green: 1, blue: 1, alpha: 0.62)
    )

    // Backdrop: faint lavender wash in light, near-black indigo in dark.
    static let bgTop = adaptive(rgb(0xF5F3FB), rgb(0x0B0B16))
    static let bgBottom = adaptive(rgb(0xE7E1F6), rgb(0x161432))

    // Card surfaces.
    static let cardFill = adaptive(
        .init(red: 1, green: 1, blue: 1, alpha: 1),
        .init(red: 1, green: 1, blue: 1, alpha: 0.07)
    )
    static let cardFillStrong = adaptive(
        .init(red: 1, green: 1, blue: 1, alpha: 1),
        .init(red: 1, green: 1, blue: 1, alpha: 0.11)
    )
    static let cardStroke = adaptive(
        rgb(0x000000, alpha: 0.06),
        rgb(0xFFFFFF, alpha: 0.12)
    )
    static let cardShadow = adaptive(
        rgb(0x2E2750, alpha: 0.12),
        rgb(0x000000, alpha: 0.0)
    )

    // Selected tab / interactive pill inside a card.
    static let pillFill = adaptive(rgb(0x000000, alpha: 0.06), rgb(0xFFFFFF, alpha: 0.12))

    static let accent = adaptive(rgb(0x2E6BE6), rgb(0x3081FA))
    static let overtime = adaptive(rgb(0x7C46F0), rgb(0x9F7BF9))
    static let undertime = adaptive(rgb(0xE2590D), rgb(0xFC8A57))
    static let dotGreen = adaptive(rgb(0x2E9E56), rgb(0x30D158))

    // Ring / circular progress.
    static let track = adaptive(rgb(0x000000, alpha: 0.06), rgb(0xFFFFFF, alpha: 0.08))
    static let ringGradient = LinearGradient(
        colors: [accent, accent],
        startPoint: .topTrailing, endPoint: .bottomLeading
    )

    // Break (clock out for a break) button.
    static let warm = LinearGradient(
        colors: [Color(red: 0.97, green: 0.43, blue: 0.42),
                 Color(red: 0.99, green: 0.58, blue: 0.32)],
        startPoint: .leading, endPoint: .trailing
    )
    static let warmShadow = Color(red: 0.99, green: 0.48, blue: 0.30)

    // Clock-in button.
    static let brand = LinearGradient(
        colors: [adaptive(rgb(0x3F82F0), rgb(0x3F8AFB)),
                 adaptive(rgb(0x2748C9), rgb(0x2C63E8))],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // Month summary card in History.
    static let monthGradient = LinearGradient(
        colors: [adaptive(rgb(0xF9F7FD), rgb(0x6B51CF)),
                 adaptive(rgb(0xF2EEFA), rgb(0x2A2059))],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let monthText = adaptive(rgb(0x14131C), rgb(0xFFFFFF))
    static let monthTextSecondary = adaptive(rgb(0x5F5B70), rgb(0xFFFFFF, alpha: 0.65))
    // Overtime sits on the tinted month card, so it needs its own reading.
    static let monthOvertime = adaptive(rgb(0x7C3AED), rgb(0xAF93FD))

    // Icon tiles (Settings rows) and small chips (History day badge).
    static let tileBlue = LinearGradient(
        colors: [adaptive(rgb(0x4C8BF0), rgb(0x398AFB)),
                 adaptive(rgb(0x2A5FD1), rgb(0x2B5CE0))],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let tileOrange = LinearGradient(
        colors: [Color(red: 0.99, green: 0.60, blue: 0.33),
                 Color(red: 0.93, green: 0.47, blue: 0.17)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let tilePurple = LinearGradient(
        colors: [adaptive(rgb(0x9B6CF5), rgb(0xA581FB)),
                 adaptive(rgb(0x6C28D9), rgb(0x7138E8))],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let tileGreen = LinearGradient(
        colors: [Color(red: 0.39, green: 0.83, blue: 0.52),
                 Color(red: 0.15, green: 0.73, blue: 0.34)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let tileGray = LinearGradient(
        colors: [adaptive(rgb(0x9C99A6), rgb(0x8D8A98)),
                 adaptive(rgb(0x837F8E), rgb(0x6E6A7C))],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let chipOvertimeFill = adaptive(
        rgb(0x7C46F0, alpha: 0.10),
        rgb(0xFFFFFF, alpha: 0.10)
    )
}

// MARK: - Surfaces

extension View {
    /// Standard content card, adaptive for both color schemes.
    func cardSurface(cornerRadius: CGFloat = 22) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.cardFill)
                .shadow(color: Theme.cardShadow, radius: 18, y: 10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.cardStroke, lineWidth: 1)
        }
    }

    /// Elevated card (hero ring area); slightly brighter fill in dark mode.
    func heroSurface(cornerRadius: CGFloat = 28) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.cardFillStrong)
                .shadow(color: Theme.cardShadow, radius: 18, y: 10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.cardStroke, lineWidth: 1)
        }
    }

    /// History's month summary card.
    func monthSurface(cornerRadius: CGFloat = 24) -> some View {
        background {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.monthGradient)
                .shadow(color: Theme.cardShadow, radius: 18, y: 10)
        }
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.cardStroke, lineWidth: 1)
        }
    }

    /// Floating capsule surface for secondary buttons and the tab bar.
    func capsuleSurface() -> some View {
        background {
            Capsule()
                .fill(Theme.cardFill)
                .shadow(color: Theme.cardShadow, radius: 18, y: 10)
        }
        .overlay {
            Capsule().strokeBorder(Theme.cardStroke, lineWidth: 1)
        }
    }

    /// Small pill status bubble.
    func pillSurface() -> some View {
        background {
            Capsule().fill(Theme.cardFill)
        }
        .overlay {
            Capsule().strokeBorder(Theme.cardStroke, lineWidth: 1)
        }
    }

    /// Full-screen adaptive backdrop for a tab's content.
    func appBackdrop() -> some View {
        background(
            LinearGradient(
                colors: [Theme.bgTop, Theme.bgBottom],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
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