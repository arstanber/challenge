import SwiftUI
import StoreKit

struct ProfileView: View {
    @State private var vm = ProfileViewModel()
    @Environment(AuthService.self) private var authService
    @State private var showJoinFamily = false
    @State private var inviteCodeInput = ""

    var body: some View {
        NavigationStack {
            List {
                if let user = vm.user {
                    Section {
                        HStack(spacing: 14) {
                            Circle()
                                .fill(.orange.gradient)
                                .frame(width: 56, height: 56)
                                .overlay {
                                    Text(String(user.email.prefix(1)).uppercased())
                                        .font(.title2.bold())
                                        .foregroundStyle(.white)
                                }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.email).font(.headline)
                                HStack(spacing: 6) {
                                    PlanBadge(plan: user.plan)
                                    RoleBadge(role: user.role)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    Section("Stats") {
                        LabeledContent("Completed", value: "\(vm.totalCompleted)")
                        LabeledContent("Failed", value: "\(vm.totalFailed)")
                    }
                }

                Section("Family") {
                    if authService.currentUser?.role == .parent {
                        if let family = vm.family {
                            HStack {
                                Label("Invite code", systemImage: "qrcode")
                                Spacer()
                                Text(family.inviteCode)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.orange)
                            }
                            .onTapGesture { UIPasteboard.general.string = family.inviteCode; Haptics.success() }

                            NavigationLink(destination: FamilyView()) {
                                Label("Manage family", systemImage: "person.2.fill")
                            }
                        } else {
                            Button {
                                Haptics.tap()
                                Task { await vm.createFamily() }
                            } label: {
                                Label("Create family", systemImage: "plus.circle.fill")
                            }
                        }
                    } else if authService.currentUser?.familyId != nil {
                        Label("Member of a family", systemImage: "person.2.circle.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Button { Haptics.tap(); showJoinFamily = true } label: {
                            Label("Join family", systemImage: "person.badge.plus")
                        }
                    }
                }

                Section("Leaderboard") {       // #1
                    NavigationLink(destination: LeaderboardView().environment(authService)) {
                        Label("Streak Leaderboard", systemImage: "trophy.fill")
                            .foregroundStyle(.yellow)
                    }
                }

                Section("Progress") {          // #16
                    NavigationLink(destination: ProgressGalleryView()) {
                        Label("Progress Gallery", systemImage: "photo.on.rectangle.angled")
                            .foregroundStyle(Color(hex: "4580FF"))
                    }
                }

                Section("Connections") {
                    NavigationLink(destination: TelegramLinkView()) {
                        Label("Telegram bot", systemImage: "paperplane.fill")
                            .foregroundStyle(Color(hex: "29A9EA"))
                    }
                    ForEach(DataConnector.allCases) { connector in
                        Button {
                            Haptics.tap()
                            Task {
                                let svc = ConnectorService.shared
                                if svc.isConnected(connector) {
                                    await svc.disconnect(connector)
                                } else {
                                    try? await svc.connect(connector)
                                }
                            }
                        } label: {
                            HStack {
                                Label(connector.displayName, systemImage: connector.icon)
                                    .foregroundStyle(connector.tint)
                                Spacer()
                                if ConnectorService.shared.isConnected(connector) {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }

                Section("Focus") {             // #11
                    NavigationLink(destination: FocusModeView()) {
                        Label("Focus Mode", systemImage: "moon.zzz.fill")
                            .foregroundStyle(.indigo)
                    }
                }

                Section("Subscription") {
                    if authService.currentUser?.isPremium == true {
                        Label("Premium active", systemImage: "star.fill")
                            .foregroundStyle(.orange)
                    } else {
                        NavigationLink(destination: PremiumView()) {
                            Label("Upgrade to Premium", systemImage: "star.circle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Haptics.warning()
                        vm.signOut()
                    } label: {
                        Label("Sign out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Profile")
            .refreshable { await vm.loadProfile() }
            .alert("Join family", isPresented: $showJoinFamily) {
                TextField("Invite code", text: $inviteCodeInput)
                    .textInputAutocapitalization(.characters)
                Button("Join") { Haptics.tap(); Task { await vm.joinFamily(code: inviteCodeInput) } }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Error", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK") { Haptics.tap(); vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
        .task { await vm.loadProfile() }
    }
}

struct PlanBadge: View {
    let plan: UserPlan
    var body: some View {
        Text(plan == .premium ? "Premium" : "Free")
            .font(.caption2.bold())
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(plan == .premium ? Color.orange.opacity(0.15) : Color.secondary.opacity(0.15), in: Capsule())
            .foregroundStyle(plan == .premium ? Color.orange : Color.secondary)
    }
}

struct RoleBadge: View {
    let role: UserRole
    var body: some View {
        if role != .individual {
            Text(role.rawValue.capitalized)
                .font(.caption2.bold())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.purple.opacity(0.15), in: Capsule())
                .foregroundStyle(.purple)
        }
    }
}

struct PremiumView: View {
    @State private var store = StoreService.shared

    private var priceLabel: String {
        store.product?.displayPrice.appending("/month") ?? "$4.99/month"
    }

    private var familyPriceLabel: String {
        store.familyProduct?.displayPrice.appending("/month") ?? "$9.99/month"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 80)).foregroundStyle(.orange)
                Text("Challenge Premium").font(.largeTitle.bold())

                // Individual plan
                VStack(alignment: .leading, spacing: 12) {
                    Text("Individual").font(.headline).foregroundStyle(.secondary)
                    FeatureRow(icon: "infinity",       text: "Unlimited challenges")
                    FeatureRow(icon: "brain",          text: "Unlimited AI verifications")
                    FeatureRow(icon: "clock.fill",     text: "Full history")
                    FeatureRow(icon: "chart.bar.fill", text: "Detailed statistics")
                    FeatureRow(icon: "flame.fill",     text: "Streak freeze (1 per week)")
                }
                .padding(20)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))

                // Family plan (#18)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Family").font(.headline).foregroundStyle(.secondary)
                        Text("NEW").font(.caption2.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color.orange))
                    }
                    FeatureRow(icon: "person.2.fill",  text: "Up to 5 family members")
                    FeatureRow(icon: "star.fill",      text: "All Premium features for everyone")
                    FeatureRow(icon: "gift.fill",      text: "Shared family leaderboard")
                }
                .padding(20)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.orange.opacity(0.3), lineWidth: 1))

                if let err = store.errorMessage {
                    Text(err).font(.caption).foregroundStyle(.red).multilineTextAlignment(.center)
                }

                // Individual CTA
                Button { Haptics.tap(); Task { await store.purchase() } } label: {
                    Group {
                        if store.isPurchasing { ProgressView().tint(.white) }
                        else { Text("Individual — \(priceLabel)").fontWeight(.semibold) }
                    }
                    .frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(.borderedProminent).tint(.orange).disabled(store.isPurchasing)

                // Family CTA (#18)
                Button { Haptics.tap(); Task { await store.purchaseFamily() } } label: {
                    Group {
                        if store.isPurchasing { ProgressView().tint(.white) }
                        else { Text("Family — \(familyPriceLabel)").fontWeight(.semibold) }
                    }
                    .frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(.borderedProminent).tint(Color(hex: "4580FF")).disabled(store.isPurchasing)

                Button { Haptics.tap(); Task { await store.restore() } } label: {
                    Text("Restore purchases").font(.subheadline).foregroundStyle(.secondary)
                }
                .disabled(store.isPurchasing)

                Text("Cancel anytime · Family plan covers up to 5 members")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .padding()
        }
        .navigationTitle("Premium")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { AnalyticsService.shared.track(.premiumPaywallShown) }
    }
}

struct FeatureRow: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).frame(width: 24).foregroundStyle(.orange)
            Text(text)
        }
    }
}

#Preview {
    ProfileView()
        .environment(AuthService.shared)
}
