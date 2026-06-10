import SwiftUI

struct MainTabView: View {
    var body: some View {
        HomeView()
    }
}

#Preview {
    MainTabView()
        .environment(AuthService.shared)
}
