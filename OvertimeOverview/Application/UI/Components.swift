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

/// Small circular header action (the + button).
struct RoundIconButton: View {
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Theme.surface))
                .overlay(Circle().strokeBorder(Theme.surfaceStroke, lineWidth: 1))
                .background(Circle().fill(Theme.surfaceShadow).shadow(radius: 8, y: 4))
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
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Theme.secondaryText)
            Text(value)
                .font(.body.bold())
                .monospacedDigit()
                .foregroundStyle(valueColor)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .cardSurface(cornerRadius: 20)
    }
}

/// Tinted rounded-rect icon badge used by Settings rows.
struct IconTile: View {
    let systemImage: String
    let fill: AnyShapeStyle

    init(systemImage: String, fill: some ShapeStyle) {
        self.systemImage = systemImage
        self.fill = AnyShapeStyle(fill)
    }

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(fill)
            }
    }
}

/// Small capsule value chip in accent color, e.g. the Settings "8h 0m" bubbles.
struct ValuePill: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(Theme.accent)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 15)
            .padding(.vertical, 7)
            .background(Theme.accentFill, in: Capsule())
    }
}

/// Circular progress ring with the elapsed time inside.
struct RingProgress: View {
    let progress: Double
    var lineWidth: CGFloat = 14
    /// Solid stroke replacing the default violet→blue gradient (the overtime ring).
    var stroke: AnyShapeStyle? = nil

    private var progressStroke: AnyShapeStyle {
        stroke ?? AnyShapeStyle(
            LinearGradient(
                colors: [Theme.overtimeFill, Theme.accent],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        )
    }

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.ringTrack, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            Circle()
                .trim(from: 0, to: max(0.02, min(1, progress)))
                .stroke(
                    progressStroke,
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.smooth, value: progress)
        }
    }
}

extension Double {
    var clampedToUnitInterval: Double { max(0, min(1, self)) }
}

extension Color {
    init(rgb hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}

/// "MON / 28" style day badge on history rows.
struct DayChip: View {
    let date: Date
    var highlight = false

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
                .foregroundStyle(highlight ? Theme.overtimeText : Theme.secondaryText)
            Text(Self.dayNumberFormatter.string(from: date))
                .font(.body.bold())
                .monospacedDigit()
                .foregroundStyle(.primary)
        }
        .frame(minWidth: 44)
        .padding(.vertical, 6)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(highlight ? Theme.chipOvertimeFill : Theme.chipFill)
        }
    }
}

// MARK: - Previews
#if DEBUG
#Preview("Components") {
    ScrollView {
        VStack(alignment: .leading, spacing: 18) {
            ScreenHeader(title: "Today", caption: "Wednesday, Sep 30") {
                RoundIconButton(systemImage: "plus") {}
            }

            RingProgress(progress: 0.39, lineWidth: 14)
                .frame(width: 232, height: 232)
                .frame(maxWidth: .infinity)

            HStack(spacing: 12) {
                StatTile(caption: "Worktime", value: "1h 44m")
                StatTile(caption: "In office", value: "2h 14m")
                StatTile(caption: "Lunch", value: "−30m", valueColor: Theme.negativeText)
            }

            HStack(spacing: 16) {
                DayChip(date: .now, highlight: true)
                DayChip(date: .now.addingTimeInterval(-86400))
                ValuePill(text: "8h 0m")
                IconTile(systemImage: "clock.fill", fill: Theme.tileBlue)
                IconTile(systemImage: "square.and.arrow.up", fill: Theme.tileGreen)
            }
        }
        .padding(16)
    }
    .appBackdrop(.today)
}
#endif