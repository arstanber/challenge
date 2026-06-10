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

                    Section("Статистика") {
                        LabeledContent("Выполнено", value: "\(vm.totalCompleted)")
                        LabeledContent("Провалено", value: "\(vm.totalFailed)")
                    }
                }

                Section("Семья") {
                    if authService.currentUser?.role == .parent {
                        if let family = vm.family {
                            HStack {
                                Label("Код приглашения", systemImage: "qrcode")
                                Spacer()
                                Text(family.inviteCode)
                                    .fontWeight(.bold)
                                    .foregroundStyle(.orange)
                            }
                            .onTapGesture { UIPasteboard.general.string = family.inviteCode; Haptics.success() }

                            NavigationLink(destination: FamilyView()) {
                                Label("Управление семьёй", systemImage: "person.2.fill")
                            }
                        } else {
                            Button {
                                Haptics.tap()
                                Task { await vm.createFamily() }
                            } label: {
                                Label("Создать семью", systemImage: "plus.circle.fill")
                            }
                        }
                    } else if authService.currentUser?.familyId != nil {
                        Label("Участник семьи", systemImage: "person.2.circle.fill")
                            .foregroundStyle(.secondary)
                    } else {
                        Button { Haptics.tap(); showJoinFamily = true } label: {
                            Label("Присоединиться к семье", systemImage: "person.badge.plus")
                        }
                    }
                }

                Section("Рейтинг") {       // #1
                    NavigationLink(destination: LeaderboardView().environment(authService)) {
                        Label("Рейтинг по сериям", systemImage: "trophy.fill")
                            .foregroundStyle(.yellow)
                    }
                }

                Section("Прогресс") {          // #16
                    NavigationLink(destination: ProgressGalleryView()) {
                        Label("Галерея прогресса", systemImage: "photo.on.rectangle.angled")
                            .foregroundStyle(Color(hex: "4580FF"))
                    }
                }

                Section("Подключения") {
                    NavigationLink(destination: ConnectorsView()) {
                        Label("Коннекторы", systemImage: "link")
                            .foregroundStyle(Color(hex: "7C4DF0"))
                    }
                    NavigationLink(destination: TelegramLinkView()) {
                        Label("Телеграм-бот", systemImage: "paperplane.fill")
                            .foregroundStyle(Color(hex: "29A9EA"))
                    }
                }

                Section("Фокус") {             // #11
                    NavigationLink(destination: FocusModeView()) {
                        Label("Режим фокуса", systemImage: "moon.zzz.fill")
                            .foregroundStyle(.indigo)
                    }
                }

                Section("Подписка") {
                    if authService.currentUser?.isPremium == true {
                        NavigationLink(destination: PremiumView()) {
                            Label("\((vm.user?.plan ?? .free).displayName) активен", systemImage: "star.fill")
                                .foregroundStyle(.orange)
                        }
                    } else {
                        NavigationLink(destination: PremiumView()) {
                            Label("Перейти на Premium", systemImage: "star.circle.fill")
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section {
                    Button(role: .destructive) {
                        Haptics.warning()
                        vm.signOut()
                    } label: {
                        Label("Выйти", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                }
            }
            .navigationTitle("Профиль")
            .refreshable { await vm.loadProfile() }
            .alert("Присоединиться к семье", isPresented: $showJoinFamily) {
                TextField("Код приглашения", text: $inviteCodeInput)
                    .textInputAutocapitalization(.characters)
                Button("Присоединиться") { Haptics.tap(); Task { await vm.joinFamily(code: inviteCodeInput) } }
                Button("Отмена", role: .cancel) {}
            }
            .alert("Ошибка", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("ОК") { Haptics.tap(); vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
        .task { await vm.loadProfile() }
    }
}

struct PlanBadge: View {
    let plan: UserPlan

    private var tint: Color {
        switch plan {
        case .free:    return .secondary
        case .premium: return .orange
        case .family:  return Color(hex: "4580FF")
        case .max:     return Color(hex: "7C4DF0")
        }
    }

    var body: some View {
        Group {
            if plan == .max {
                Text(plan.displayName)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(
                        LinearGradient(
                            colors: [Color(hex: "7C4DF0"), Color(hex: "5B2FD6")],
                            startPoint: .leading,
                            endPoint: .trailing
                        ),
                        in: Capsule()
                    )
                    .foregroundStyle(.white)
            } else {
                Text(plan.displayName)
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(tint.opacity(0.15), in: Capsule())
                    .foregroundStyle(tint)
            }
        }
    }
}

struct RoleBadge: View {
    let role: UserRole

    private var title: String {
        switch role {
        case .parent:     return "Родитель"
        case .child:      return "Ребёнок"
        case .individual: return ""
        }
    }

    var body: some View {
        if role != .individual {
            Text(title)
                .font(.caption2.bold())
                .padding(.horizontal, 6).padding(.vertical, 2)
                .background(.purple.opacity(0.15), in: Capsule())
                .foregroundStyle(.purple)
        }
    }
}

#Preview {
    ProfileView()
        .environment(AuthService.shared)
}
