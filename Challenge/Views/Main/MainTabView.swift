import SwiftUI

struct MainTabView: View {
    @State private var selectedTab = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            ActivitiesView()
                .tabItem {
                    Label("My", systemImage: "list.bullet.circle.fill")
                }
                .tag(0)

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.circle.fill")
                }
                .tag(1)
        }
    }
}

#Preview {
    MainTabView()
        .environment(AuthService.shared)
}
