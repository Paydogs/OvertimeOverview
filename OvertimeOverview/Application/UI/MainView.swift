//
//  MainView.swift
//  OvertimeOverview
//
//

import SwiftUI

struct MainView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label(Keys.tabToday, systemImage: "clock") }
            HistoryView()
                .tabItem { Label(Keys.tabHistory, systemImage: "calendar") }
            SettingsView()
                .tabItem { Label(Keys.tabSettings, systemImage: "gearshape") }
        }
        .tint(Theme.accent)
    }
}

#Preview {
    MainView()
        .environment(previewAppModel(seed: .clockedIn))
        .preferredColorScheme(.dark)
}

#Preview("Light") {
    MainView()
        .environment(previewAppModel(seed: .clockedIn))
        .preferredColorScheme(.light)
}