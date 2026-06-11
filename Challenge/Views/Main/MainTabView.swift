import SwiftUI

struct MainTabView: View {
    @Environment(AuthService.self) private var authService
    /// Last paid plan we already congratulated -- so the popup fires once
    /// per plan change (purchase, upgrade, or server-side grant).
    @AppStorage("celebratedPlan") private var celebratedPlan = UserPlan.free.rawValue
    @State private var celebrationPlan: UserPlan?

    var body: some View {
        HomeView()
            // Warm the AI-quota cache so canUse/remaining reflect the server state
            .task { await RateLimiterService.shared.fetchUsage() }
            .task { checkPlanCelebration() }
            .onChange(of: authService.currentUser?.plan) { checkPlanCelebration() }
            .sheet(item: $celebrationPlan) { plan in
                PlanCelebrationView(plan: plan)
            }
    }

    private func checkPlanCelebration() {
        guard let plan = authService.currentUser?.plan else { return }
        if plan == .free {
            // Reset so a future (re)subscription celebrates again.
            celebratedPlan = UserPlan.free.rawValue
            return
        }
        guard celebratedPlan != plan.rawValue else { return }
        celebratedPlan = plan.rawValue
        celebrationPlan = plan
    }
}

#Preview {
    MainTabView()
        .environment(AuthService.shared)
}
