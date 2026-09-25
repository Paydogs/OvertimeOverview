//
//  Theme.swift
//  OvertimeOverview
//

import SwiftUI

enum Theme {
    static let brandColors: [Color] = [
        Color(red: 106 / 255, green: 90 / 255, blue: 224 / 255),
        Color(red: 166 / 255, green: 75 / 255, blue: 244 / 255),
    ]
    static let brand = LinearGradient(
        colors: brandColors,
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let warm = LinearGradient(
        colors: [Color(red: 1, green: 107 / 255, blue: 107 / 255),
                 Color(red: 1, green: 142 / 255, blue: 83 / 255)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Midnight glass backdrop: deep navy into violet, darkest at the top.
    static let background = LinearGradient(
        colors: [Color(red: 0.03, green: 0.05, blue: 0.12),
                 Color(red: 0.10, green: 0.06, blue: 0.19)],
        startPoint: .top, endPoint: .bottom
    )

    static let accent = Color(red: 166 / 255, green: 75 / 255, blue: 244 / 255)
    static let undertime = Color(red: 1, green: 107 / 255, blue: 107 / 255)
}

// MARK: - Glass surfaces

extension View {
    /// Frosted card with a hairline light stroke — content surface.
    func glassCard(cornerRadius: CGFloat = 24) -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
    }

    /// Frosted capsule — floating action surface.
    func glassCapsule() -> some View {
        background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 1))
    }

    /// Small frosted pill for status/legend text.
    func glassPill() -> some View {
        background(.ultraThinMaterial, in: Capsule())
            .overlay(Capsule().strokeBorder(Color.white.opacity(0.10), lineWidth: 1))
    }

    /// Full-screen midnight backdrop for a tab's content.
    func midnightBackdrop() -> some View {
        background(Theme.background.ignoresSafeArea())
    }
}