import SwiftUI

struct MainTabView: View {
    @Environment(AuthService.self) private var authService
    /// Last paid plan we already congratulated -- so the popup fires once
    /// per plan change (purchase, upgrade, or server-side grant).
    @AppStorage("celebratedPlan") private var celebratedPlan = UserPlan.free.rawValue
    @State private var celebrationPlan: UserPlan?
    @State private var joinVM = ProfileViewModel()
    @State private var showJoinPrompt = false
    @State private var joining = false

    private var canJoinPending: Bool {
        (authService.pendingFamilyCode?.isEmpty == false) && authService.currentUser?.familyId == nil
    }

    var body: some View {
        HomeView()
            .overlay(alignment: .top) { OfflineBanner() }
            // Warm the AI-quota cache so canUse/remaining reflect the server state
            .task { await RateLimiterService.shared.fetchUsage() }
            .task { checkPlanCelebration() }
            .onChange(of: authService.currentUser?.plan) { checkPlanCelebration() }
            .task(id: authService.pendingFamilyCode) { if canJoinPending { showJoinPrompt = true } }
            .sheet(item: $celebrationPlan) { plan in
                PlanCelebrationView(plan: plan)
            }
            .alert("Присоединиться к семье?", isPresented: $showJoinPrompt) {
                Button("Присоединиться") {
                    Task {
                        joining = true
                        await joinVM.consumePendingInvite()
                        await authService.refreshProfile()
                        joining = false
                    }
                }
                Button("Отмена", role: .cancel) { authService.pendingFamilyCode = nil }
            } message: {
                Text("Тебя пригласили в семью по коду \(authService.pendingFamilyCode ?? ""). Присоединиться сейчас?")
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
