//
//  OvertimeOverviewApp.swift
//  OvertimeOverview
//

import SwiftUI

@main
struct OvertimeOverviewApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    @Environment(\.scenePhase) private var scenePhase
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(appModel)
        }
        .onChange(of: scenePhase) { _, phase in
            // Widget punches may have changed data while we were backgrounded.
            guard phase == .active else { return }
            Task { await appModel.viewModel.refresh() }
        }
    }
}
