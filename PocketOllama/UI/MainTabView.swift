import SwiftUI

public struct MainTabView: View {
    @State private var selectedTab: Int = 0

    public init() {
        UITabBar.appearance().backgroundColor = UIColor(PocketTheme.bgDeep)
        UITabBar.appearance().unselectedItemTintColor = UIColor(PocketTheme.textMuted)
    }

    public var body: some View {
        TabView(selection: $selectedTab) {
            DashboardBentoView()
                .tabItem {
                    Image(systemName: "square.grid.2x2.fill")
                    Text("Dashboard")
                }
                .tag(0)

            ChatPlaygroundView()
                .tabItem {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                    Text("Playground")
                }
                .tag(1)

            ModelStoreView()
                .tabItem {
                    Image(systemName: "shippingbox.fill")
                    Text("Models")
                }
                .tag(2)
        }
        .accentColor(PocketTheme.cyan)
    }
}
