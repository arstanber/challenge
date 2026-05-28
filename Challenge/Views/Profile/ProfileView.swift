import SwiftUI

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
                            .onTapGesture { UIPasteboard.general.string = family.inviteCode }

                            NavigationLink(destination: FamilyView()) {
                                Label("Manage family", systemImage: "person.2.fill")
                            }
                        } else {
                            Button {
                                Task { await vm.createFamily() }
                            } label: {
                                Label("Create family", systemImage: "plus.circle.fill")
                            }
                        }
                    } else if authService.currentUser?.familyId != nil {
                        Label("Member of a family", systemImage: "person.2.circle.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Button { showJoinFamily = true } label: {
                            Label("Join family", systemImage: "person.badge.plus")
                        }
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
                Button("Join") { Task { await vm.joinFamily(code: inviteCodeInput) } }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Error", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK") { vm.errorMessage = nil }
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
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 80)).foregroundStyle(.orange)
                Text("Challenge Premium").font(.largeTitle.bold())

                VStack(alignment: .leading, spacing: 12) {
                    FeatureRow(icon: "infinity", text: "Unlimited challenges")
                    FeatureRow(icon: "brain", text: "Unlimited AI verifications")
                    FeatureRow(icon: "clock.fill", text: "Full history")
                    FeatureRow(icon: "chart.bar.fill", text: "Detailed statistics")
                    FeatureRow(icon: "flame.fill", text: "Streak freeze (1 per week)")
                }
                .padding(20)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))

                Button {
                    // StoreKit integration TBD
                } label: {
                    Text("Subscribe for $4.99/month")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(.borderedProminent).tint(.orange)

                Text("Cancel anytime · 3-day free trial")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Premium")
        .navigationBarTitleDisplayMode(.inline)
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
