import SwiftUI

public struct MainTabView: View {
    @State private var selectedTab: Int = 0

    init() {
        // Configure native iOS TabBar appearance to transparent dark glass
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = UIColor(red: 0.04, green: 0.05, blue: 0.09, alpha: 0.95)
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
                    Label("Playground", systemImage: "bubble.left.and.bubble.right.fill")
                }
                .tag(1)

            ModelStoreView()
                .tabItem {
                    Label("Model Hub", systemImage: "cube.box.fill")
                }
                .tag(2)
        }
        .accentColor(PocketTheme.cyan)
    }
}
