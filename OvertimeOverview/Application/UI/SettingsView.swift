//
//  SettingsView.swift
//  OvertimeOverview
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var pickingWork = false
    @State private var pickingLunch = false
    @State private var importing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ScreenHeader(title: Keys.tabSettings)

                sectionCaption(Keys.worktimeTitle)
                worktimeCard
                Text(Keys.settingsOfficeTarget(Formatters.duration(appModel.settings.officeTarget)))
                    .font(.subheadline)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 6)

                sectionCaption(Keys.settingsHaptics)
                hapticsCard

                sectionCaption(Keys.settingsBackup)
                backupCard

                Text(Self.versionFooter)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .font(.footnote)
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
        }
        .contentMargins(.bottom, 24)
        .appBackdrop(.settings)
        .sheet(
            isPresented: $pickingWork,
            content: {
                DurationPickerSheet(
                    title: Keys.settingsPickWork,
                    minutes: Int(appModel.settings.workSeconds / 60)
                ) { appModel.settings.updateWork(minutes: $0) }
            }
        )
        .sheet(
            isPresented: $pickingLunch,
            content: {
                DurationPickerSheet(
                    title: Keys.settingsPickLunch,
                    minutes: Int(appModel.settings.lunchSeconds / 60)
                ) { appModel.settings.updateLunch(minutes: $0) }
            }
        )
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { appModel.preferences.readImport(at: url) }
        }
        .confirmationDialog(
            Keys.backupImportQuestion,
            isPresented: importBinding
        ) {
            Button(Keys.backupReplace) { appModel.preferences.importBackup(replace: true) }
            Button(Keys.backupMerge) { appModel.preferences.importBackup(replace: false) }
            Button(Keys.commonCancel, role: .cancel) { appModel.preferences.cancelImport() }
        }
        .sheet(item: shareItemBinding) { item in
            ShareSheet(url: item.url)
        }
        .alert(
            Keys.settingsBackup,
            isPresented: alertBinding,
            presenting: appModel.preferences.alertMessage
        ) { _ in } message: { message in Text(message) }
    }

    // MARK: - Bindings (thin wrappers over the view model)

    private var importBinding: Binding<Bool> {
        Binding(
            get: { appModel.preferences.pendingImport != nil },
            set: { if !$0 { appModel.preferences.cancelImport() } }
        )
    }

    private var shareItemBinding: Binding<SettingsViewModel.ShareItem?> {
        Binding(
            get: { appModel.preferences.shareItem },
            set: { if $0 == nil { appModel.preferences.dismissShare() } }
        )
    }

    private var alertBinding: Binding<Bool> {
        Binding(
            get: { appModel.preferences.alertMessage != nil },
            set: { if !$0 { appModel.preferences.dismissAlert() } }
        )
    }

    private var hapticsEnabledBinding: Binding<Bool> {
        Binding(
            get: { appModel.haptics.settings.enabled },
            set: { appModel.preferences.setHapticsEnabled($0) }
        )
    }

    private var strengthBinding: Binding<Double> {
        Binding(
            get: { appModel.haptics.settings.strength },
            set: { appModel.preferences.setHapticStrength($0) }
        )
    }

    private var patternBinding: Binding<HapticPattern> {
        Binding(
            get: { appModel.haptics.settings.pattern },
            set: { appModel.preferences.setHapticPattern($0) }
        )
    }

    private var syncBinding: Binding<Bool> {
        Binding(
            get: { appModel.settings.iCloudSyncEnabled },
            set: { appModel.preferences.setSyncEnabled($0) }
        )
    }

    // MARK: - Rows (layout only; every value comes from the view models)

    private func sectionCaption(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 6)
    }

    private var worktimeCard: some View {
        VStack(spacing: 0) {
            rowButton(
                icon: "clock.fill",
                tileFill: Theme.tileBlue,
                title: Keys.settingsWork,
                subtitle: Keys.settingsWorkSubtitle
            ) {
                ValuePill(text: Formatters.duration(appModel.settings.workSeconds))
            } action: {
                pickingWork = true
            }
            rowDivider
            rowButton(
                icon: "fork.knife",
                tileFill: Theme.tileOrange,
                title: Keys.settingsLunch,
                subtitle: Keys.settingsLunchSubtitle
            ) {
                ValuePill(text: Formatters.duration(appModel.settings.lunchSeconds))
            } action: {
                pickingLunch = true
            }
        }
        .cardSurface(cornerRadius: 22)
    }

    private var hapticsCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                IconTile(
                    systemImage: "iphone.radiowaves.left.and.right",
                    fill: Theme.tilePurple
                )
                VStack(alignment: .leading, spacing: 1) {
                    Text(Keys.settingsHaptics)
                        .foregroundStyle(.primary)
                    Text(Keys.settingsHapticsSubtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                }
                Spacer()
                Toggle("", isOn: hapticsEnabledBinding)
                    .labelsHidden()
            }
            .settingsRow()

            if appModel.haptics.settings.enabled {
                rowDivider
                HStack {
                    Text(Keys.settingsHapticPattern)
                        .foregroundStyle(.primary)
                    Spacer()
                    Picker("", selection: patternBinding) {
                        ForEach(HapticPattern.allCases, id: \.self) { pattern in
                            Text(appModel.preferences.hapticPatternLabel(pattern)).tag(pattern)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
                .settingsRow()

                rowDivider
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(Keys.settingsHapticStrengthLabel)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(strengthPercent)
                            .monospacedDigit()
                            .foregroundStyle(Theme.secondaryText)
                    }
                    Slider(value: strengthBinding, in: 0.1...1)
                }
                .settingsRow()

                rowDivider
                Button(action: { appModel.preferences.testHaptics() }) {
                    Text(Keys.settingsTestHaptics)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .foregroundStyle(Theme.accent)
                }
                .settingsRow()
            }
        }
        .cardSurface(cornerRadius: 22)
    }

    private var backupCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                IconTile(systemImage: "cloud", fill: Theme.tileBlue)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Keys.settingsIcloudSync)
                        .foregroundStyle(.primary)
                    Text(Keys.settingsIcloudSyncSubtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Toggle("", isOn: syncBinding)
                    .labelsHidden()
            }
            .settingsRow()
            rowDivider
            rowButton(
                icon: "square.and.arrow.up",
                tileFill: Theme.tileGreen,
                title: Keys.settingsExport,
                subtitle: nil
            ) {
                chevron
            } action: {
                appModel.preferences.exportBackup()
            }
            rowDivider
            rowButton(
                icon: "square.and.arrow.down",
                tileFill: Theme.tileGray,
                title: Keys.settingsImport,
                subtitle: nil
            ) {
                chevron
            } action: {
                importing = true
            }
        }
        .cardSurface(cornerRadius: 22)
    }

    private var chevron: some View {
        Image(systemName: "chevron_right")
            .font(.footnote.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
    }

    private var rowDivider: some View {
        Rectangle()
            .fill(Theme.separator)
            .frame(height: 1)
    }

    private func rowButton<Trailing: View>(
        icon: String,
        tileFill: Color,
        title: String,
        subtitle: String?,
        @ViewBuilder trailing: () -> Trailing,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticsController.play(appModel.haptics.settings)
            action()
        } label: {
            HStack(spacing: 14) {
                IconTile(systemImage: icon, fill: tileFill)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .foregroundStyle(.primary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                trailing()
            }
            .settingsRow()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var strengthPercent: String {
        "\(Int((appModel.haptics.settings.strength * 100).rounded()))%"
    }

    private static var versionFooter: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "OvertimeOverview v\(version) (\(build))"
    }
}

extension View {
    /// Horizontal breathing room for a row inside a settings card.
    fileprivate func settingsRow() -> some View {
        padding(.horizontal, 18)
            .padding(.vertical, 12)
    }
}

/// UIKit share sheet for the exported file.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Hours:minutes wheel picker used for work time and lunch length.
private struct DurationPickerSheet: View {
    let title: String
    let minutes: Int
    let onConfirm: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pickerDate: Date = .now

    var body: some View {
        NavigationStack {
            DatePicker(title, selection: $pickerDate, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .padding()
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Keys.commonCancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(Keys.commonOk) {
                            let components = Calendar.current.dateComponents([.hour, .minute], from: pickerDate)
                            onConfirm((components.hour ?? 0) * 60 + (components.minute ?? 0))
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium])
        .onAppear {
            let calendar = Calendar.current
            pickerDate = calendar.date(
                from: DateComponents(
                    year: 2000, month: 1, day: 1,
                    hour: minutes / 60, minute: minutes % 60
                )
            )!
        }
    }
}
// MARK: - Previews

#Preview("Settings") {
    SettingsView()
        .environment(previewAppModel(seed: .empty))
        .preferredColorScheme(.dark)
}

#Preview("Settings — light") {
    SettingsView()
        .environment(previewAppModel(seed: .empty))
        .preferredColorScheme(.light)
}

#Preview("Duration picker sheet") {
    DurationPickerSheet(title: "Work time", minutes: 450) { _ in }
        .preferredColorScheme(.dark)
}