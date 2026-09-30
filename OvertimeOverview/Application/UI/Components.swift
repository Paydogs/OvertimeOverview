//
//  Components.swift
//  OvertimeOverview
//
//

import SwiftUI

/// Large screen title with an optional date caption and a trailing round button.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var caption: String?
    @ViewBuilder var trailing: Trailing

    init(title: String, caption: String? = nil, @ViewBuilder trailing: () -> Trailing = { EmptyView() }) {
        self.title = title
        self.caption = caption
        self.trailing = trailing()
    }

    var body: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 4) {
                if let caption {
                    Text(caption)
                        .font(.caption.weight(.semibold))
                        .tracking(0.6)
                        .textCase(.uppercase)
                        .foregroundStyle(Theme.secondaryText)
                }
                Text(title)
                    .font(DisplayFont.timer(36))
                    .foregroundStyle(.primary)
            }
            Spacer()
            trailing
                .alignmentGuide(.bottom) { $0.height + 4 }
        }
    }
}

/// Small circular header action (the + and share buttons).
struct RoundIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.cardFill))
                .overlay(Circle().strokeBorder(Theme.cardStroke, lineWidth: 1))
                .background(Circle().fill(Theme.cardShadow).shadow(radius: 8, y: 4))
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
    }
}

/// One caption + bold value tile in the Today stat row.
struct StatTile: View {
    let caption: String
    let value: String
    var valueColor: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(caption)
                .font(.footnote)
                .foregroundStyle(Theme.secondaryText)
            Text(value)
                .font(.title3.bold())
                .monospacedDigit()
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .cardSurface(cornerRadius: 18)
    }
}

/// Tinted rounded-rect icon badge used by Settings rows.
struct IconTile: View {
    let systemImage: String
    let fill: LinearGradient

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 38, height: 38)
            .background(fill, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

/// Small capsule value chip in accent color, e.g. the Settings "8h 0m" bubbles.
struct ValuePill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body.bold())
            .monospacedDigit()
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(Theme.accent.opacity(0.12), in: Capsule())
    }
}

/// Circular progress ring with the elapsed time inside.
struct RingProgress: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.track, style: StrokeStyle(lineWidth: 18, lineCap: .round))
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(
                    Theme.ringGradient,
                    style: StrokeStyle(lineWidth: 18, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.6), value: progress)
        }
    }
}

/// "MON / 28" style day badge on history rows.
struct DayChip: View {
    let date: Date

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()

    private static let dayNumberFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d")
        return formatter
    }()

    var body: some View {
        VStack(spacing: 0) {
            Text(Self.weekdayFormatter.string(from: date).uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Theme.overtime)
            Text(Self.dayNumberFormatter.string(from: date))
                .font(.body.bold())
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.chipOvertimeFill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}