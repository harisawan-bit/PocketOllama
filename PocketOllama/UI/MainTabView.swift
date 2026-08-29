import SwiftUI

public struct MainTabView: View {
    @State private var selectedTab: Int = 0

    init() {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.03, green: 0.04, blue: 0.06, alpha: 1.0)
        appearance.shadowColor = UIColor.white.withAlphaComponent(0.08)

        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            DashboardBentoView()
                .tabItem {
                    Label("Server HUD", systemImage: "cpu.fill")
                }
                .tag(0)

            ChatPlaygroundView()
                .tabItem {
                    Label("Terminal", systemImage: "terminal.fill")
                }
                .tag(1)

            ModelStoreView()
                .tabItem {
                    Label("Models", systemImage: "folder.fill")
                }
                .tag(2)
        }
        .accentColor(PocketTheme.devCyan)
    }
}
