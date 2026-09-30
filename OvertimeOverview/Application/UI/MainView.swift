//
//  MainView.swift
//  OvertimeOverview
//
//

import SwiftUI

enum MainTab: String, CaseIterable {
    case today, history, settings

    var title: String {
        switch self {
        case .today: Keys.tabToday
        case .history: Keys.tabHistory
        case .settings: Keys.tabSettings
        }
    }

    var icon: String {
        switch self {
        case .today: "clock"
        case .history: "calendar"
        case .settings: "gearshape"
        }
    }
}

struct MainView: View {
    @State private var selection: MainTab = .today

    var body: some View {
        Group {
            switch selection {
            case .today: TodayView()
            case .history: HistoryView()
            case .settings: SettingsView()
            }
        }
        .safeAreaInset(edge: .bottom) { FloatingTabBar(selection: $selection) }
    }
}

/// Floating capsule bar under the content, replacing the system TabView.
private struct FloatingTabBar: View {
    @Binding var selection: MainTab
    @Environment(AppModel.self) private var appModel

    var body: some View {
        HStack(spacing: 4) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                tabButton(tab)
            }
        }
        .padding(8)
        .cardSurface(cornerRadius: 36)
        .padding(.horizontal, 16)
        .padding(.bottom, 6)
        .animation(.easeOut(duration: 0.18), value: selection)
    }

    private func tabButton(_ tab: MainTab) -> some View {
        let selected = selection == tab
        return Button {
            HapticsController.play(appModel.haptics.settings)
            selection = tab
        } label: {
            VStack(spacing: 2) {
                Image(systemName: tab.icon)
                    .font(.system(size: 20, weight: .medium))
                    .frame(height: 22)
                Text(tab.title)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .foregroundStyle(selected ? Theme.accent : .primary)
            .background {
                if selected {
                    Capsule().fill(Theme.pillFill)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    MainView()
        .environment(previewAppModel(seed: .clockedIn))
}

#Preview("Light") {
    MainView()
        .environment(previewAppModel(seed: .clockedIn))
        .preferredColorScheme(.light)
}