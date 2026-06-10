import SwiftUI

struct MainTabView: View {
    var body: some View {
        HomeView()
            // Warm the AI-quota cache so canUse/remaining reflect the server state
            .task { await RateLimiterService.shared.fetchUsage() }
    }
}

#Preview {
    MainTabView()
        .environment(AuthService.shared)
}
