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
        Form {
            Section(Keys.worktimeTitle) {
                valueRow(
                    title: Keys.settingsWork,
                    subtitle: Keys.settingsWorkSubtitle,
                    value: Formatters.duration(appModel.settings.workSeconds)
                ) { pickingWork = true }
                valueRow(
                    title: Keys.settingsLunch,
                    subtitle: Keys.settingsLunchSubtitle,
                    value: Formatters.duration(appModel.settings.lunchSeconds)
                ) { pickingLunch = true }
                Text(Keys.settingsOfficeTarget(Formatters.duration(appModel.settings.officeTarget)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: hapticsBinding) {
                    VStack(alignment: .leading) {
                        Text(Keys.settingsHaptics)
                        Text(Keys.settingsHapticsSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if appModel.haptics.settings.enabled {
                    VStack(alignment: .leading) {
                        Text(Keys.settingsHapticStrength(Int(appModel.haptics.settings.strength * 100)))
                        Slider(value: strengthBinding, in: 0.1...1)
                    }
                    Picker(Keys.settingsHapticPattern, selection: patternBinding) {
                        ForEach(HapticPattern.allCases, id: \.self) { pattern in
                            Text(Self.patternLabel(pattern)).tag(pattern)
                        }
                    }
                    Button(Keys.settingsTestHaptics) {
                        HapticsController.play(appModel.haptics.settings)
                    }
                }
            }

            Section(Keys.settingsBackup) {
                Button(Keys.settingsExport) { exportBackup() }
                Button(Keys.settingsImport) { importing = true }
            }

            Section {
                Text(Self.versionFooter)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
            }
        }
        .scrollContentBackground(.hidden)
        .midnightBackdrop()
        .navigationTitle(Keys.tabSettings)
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

    // MARK: - Rows

    private func valueRow(title: String, subtitle: String, value: String, onTap: @escaping () -> Void) -> some View {
        Button(action: {
            HapticsController.play(appModel.haptics.settings)
            onTap()
        }) {
            HStack {
                VStack(alignment: .leading) {
                    Text(title).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(value).bold()
                Image(systemName: "chevron_right").font(.caption).foregroundStyle(.secondary)
            }
        }
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