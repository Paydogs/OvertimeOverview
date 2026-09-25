//
//  ContentView.swift
//  OvertimeOverview
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label(Keys.tabToday, systemImage: "clock") }
            HistoryView()
                .tabItem { Label(Keys.tabHistory, systemImage: "calendar") }
            SettingsView()
                .tabItem { Label(Keys.tabSettings, systemImage: "gearshape") }
        }
        // Midnight glass only reads on dark; the design is dark-mode-native.
        .preferredColorScheme(.dark)
    }
}

#Preview {
    ContentView()
}
