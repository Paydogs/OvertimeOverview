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
    @State private var pendingImport: Data?
    @State private var shareURL: URL?
    @State private var alertMessage: String?

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
        .appBackdrop()
        .sheet(isPresented: $pickingWork) {
            DurationPickerSheet(title: Keys.settingsPickWork, minutes: Int(appModel.settings.workSeconds / 60)) {
                appModel.settings.updateWork(minutes: $0)
            }
        }
        .sheet(isPresented: $pickingLunch) {
            DurationPickerSheet(title: Keys.settingsPickLunch, minutes: Int(appModel.settings.lunchSeconds / 60)) {
                appModel.settings.updateLunch(minutes: $0)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { readImport(url) }
        }
        .confirmationDialog(
            Keys.backupImportQuestion,
            isPresented: Binding(
                get: { pendingImport != nil },
                set: { if !$0 { pendingImport = nil } }
            )
        ) {
            Button(Keys.backupReplace) { importBackup(replace: true) }
            Button(Keys.backupMerge) { importBackup(replace: false) }
            Button(Keys.commonCancel, role: .cancel) { pendingImport = nil }
        }
        .sheet(item: shareBinding) { item in
            ShareSheet(url: item.url)
        }
        .alert(
            Keys.settingsBackup,
            isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } }),
            presenting: alertMessage
        ) { _ in } message: { message in Text(message) }
    }

    private func sectionCaption(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.secondaryText)
            .padding(.horizontal, 6)
    }

    private var worktimeCard: some View {
        VStack(spacing: 0) {
            rowButton(
                icon: "clock",
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
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
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
                    systemImage: "iphone.gen3.radiowaves.left.and.right",
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
                Toggle("", isOn: hapticsBinding)
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
                            Text(Self.patternLabel(pattern)).tag(pattern)
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
                Button {
                    HapticsController.play(appModel.haptics.settings)
                } label: {
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
            rowButton(
                icon: "square.and.arrow.up",
                tileFill: Theme.tileGreen,
                title: Keys.settingsExport,
                subtitle: nil
            ) {
                Image(systemName: "chevron_right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            } action: {
                exportBackup()
            }
            rowDivider
            rowButton(
                icon: "square.and.arrow.down",
                tileFill: Theme.tileGray,
                title: Keys.settingsImport,
                subtitle: nil
            ) {
                Image(systemName: "chevron_right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.secondaryText)
            } action: {
                importing = true
            }
        }
        .cardSurface(cornerRadius: 22)
    }

    private var strengthPercent: String {
        "\(Int((appModel.haptics.settings.strength * 100).rounded()))%"
    }

    // MARK: - Shared row scaffolding

    private var rowDivider: some View {
        Rectangle()
            .fill(Theme.cardStroke)
            .frame(height: 1)
    }

    private func rowButton<Trailing: View>(
        icon: String,
        tileFill: LinearGradient,
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

    // MARK: - Backup

    private func exportBackup() {
        guard let data = appModel.viewModel.exportBackup(settings: appModel.settings),
              let url = try? Self.writeTempJSON(data)
        else {
            alertMessage = Keys.backupExportFailed
            return
        }
        shareURL = url
    }

    private static func writeTempJSON(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("overtimeoverview-\(Formatters.exportStamp(Date())).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func readImport(_ url: URL) {
        guard url.startAccessingSecurityScopedResource(),
              let data = try? Data(contentsOf: url)
        else {
            alertMessage = Keys.backupFailed
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        pendingImport = data
    }

    private func importBackup(replace: Bool) {
        guard let data = pendingImport else { return }
        pendingImport = nil
        Task {
            if let count = await appModel.viewModel.importBackup(
                data: data, replace: replace, settings: appModel.settings
            ) {
                alertMessage = Keys.backupImported(count)
            } else {
                alertMessage = Keys.backupFailed
            }
        }
    }

    // MARK: - Bindings

    private var hapticsBinding: Binding<Bool> {
        Binding(
            get: { appModel.haptics.settings.enabled },
            set: { newValue in
                var settings = appModel.haptics.settings
                settings.enabled = newValue
                appModel.haptics.update(settings)
                if newValue { HapticsController.play(settings) }
            }
        )
    }

    private var strengthBinding: Binding<Double> {
        Binding(
            get: { appModel.haptics.settings.strength },
            set: { newValue in
                var settings = appModel.haptics.settings
                settings.strength = newValue
                appModel.haptics.update(settings)
            }
        )
    }

    private var patternBinding: Binding<HapticPattern> {
        Binding(
            get: { appModel.haptics.settings.pattern },
            set: { newValue in
                var settings = appModel.haptics.settings
                settings.pattern = newValue
                appModel.haptics.update(settings)
            }
        )
    }

    private var shareBinding: Binding<ShareURL?> {
        Binding(get: { shareURL.map(ShareURL.init) }, set: { if $0 == nil { shareURL = nil } })
    }

    private static func patternLabel(_ pattern: HapticPattern) -> String {
        switch pattern {
        case .single: Keys.hapticSingle
        case .double: Keys.hapticDouble
        case .triple: Keys.hapticTriple
        case .long: Keys.hapticLong
        }
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

/// Wrapper so `.sheet(item:)` can present a URL.
private struct ShareURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
    init(_ url: URL) { self.url = url }
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