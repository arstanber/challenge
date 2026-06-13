import SwiftUI

struct FamilyView: View {
    @State private var vm = ProfileViewModel()
    @State private var joinCode = ""
    @State private var showLeave = false
    @State private var showDelete = false
    @State private var memberToRemove: FamilyMember?

    private var role: UserRole { vm.user?.role ?? .individual }

    var body: some View {
        List {
            switch role {
            case .parent:    parentSections
            case .child:     childSection
            case .individual: setupSection
            }
        }
        .navigationTitle("Семья")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await vm.loadProfile() }
        .task { await vm.loadProfile() }
        .confirmationDialog("Покинуть семью?", isPresented: $showLeave, titleVisibility: .visible) {
            Button("Покинуть", role: .destructive) { Task { await vm.leaveFamily() } }
            Button("Отмена", role: .cancel) {}
        }
        .confirmationDialog("Удалить семью?", isPresented: $showDelete, titleVisibility: .visible) {
            Button("Удалить", role: .destructive) { Task { await vm.deleteFamily() } }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Все участники будут откреплены. Подписки это не затронет.")
        }
        .confirmationDialog("Убрать участника?", isPresented: .init(
            get: { memberToRemove != nil },
            set: { if !$0 { memberToRemove = nil } }
        ), titleVisibility: .visible) {
            Button("Убрать", role: .destructive) {
                if let m = memberToRemove { Task { await vm.removeMember(m) } }
                memberToRemove = nil
            }
            Button("Отмена", role: .cancel) { memberToRemove = nil }
        }
    }

    // MARK: Parent

    @ViewBuilder private var parentSections: some View {
        if let family = vm.family {
            Section("Код семьи") {
                HStack {
                    Text(family.inviteCode)
                        .font(.title2.bold().monospaced())
                        .foregroundStyle(.orange)
                    Spacer()
                    Button {
                        UIPasteboard.general.string = family.inviteCode
                        Haptics.success()
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                }
                Text("Поделись этим кодом с детьми, чтобы они могли присоединиться.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }

        Section("Дети (\(vm.children.count))") {
            if vm.children.isEmpty {
                Text("Пока нет детей. Поделись кодом приглашения.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(vm.children) { member in
                    memberRow(member)
                        .swipeActions {
                            Button(role: .destructive) { memberToRemove = member } label: {
                                Label("Убрать", systemImage: "person.fill.xmark")
                            }
                        }
                }
            }
        }

        Section {
            Button(role: .destructive) { Haptics.warning(); showDelete = true } label: {
                Text("Удалить семью")
            }
        }
    }

    // MARK: Child

    @ViewBuilder private var childSection: some View {
        Section {
            HStack(spacing: 12) {
                Circle().fill(.purple.opacity(0.2)).frame(width: 40, height: 40)
                    .overlay { Image(systemName: "person.3.fill").foregroundStyle(.purple) }
                Text("Ты в семейной группе")
                    .font(.subheadline.bold())
            }
        }
        Section {
            Button(role: .destructive) { Haptics.warning(); showLeave = true } label: {
                Text("Покинуть семью")
            }
        }
    }

    // MARK: Individual (setup)

    @ViewBuilder private var setupSection: some View {
        Section("Создать семью") {
            Text("Создай семейную группу, чтобы видеть рейтинг детей и делиться подпиской.")
                .font(.caption).foregroundStyle(.secondary)
            Button {
                Haptics.tap()
                Task { await vm.createFamily() }
            } label: {
                Label("Создать семью", systemImage: "person.3.fill")
            }
        }

        Section("Присоединиться по коду") {
            TextField("Код приглашения", text: $joinCode)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            Button {
                Haptics.tap()
                let code = joinCode.trimmingCharacters(in: .whitespaces)
                Task { await vm.joinFamily(code: code) }
            } label: {
                Label("Присоединиться", systemImage: "arrow.right.circle.fill")
            }
            .disabled(joinCode.trimmingCharacters(in: .whitespaces).count < 4)
        }

        if let error = vm.errorMessage {
            Section { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }

    private func memberRow(_ member: FamilyMember) -> some View {
        HStack {
            Circle()
                .fill(.purple.opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay { Image(systemName: "person.fill").foregroundStyle(.purple) }
            VStack(alignment: .leading, spacing: 2) {
                Text(member.childUser?.email ?? "Ребёнок")
                    .font(.subheadline.bold())
                Text("Присоединился \(member.joinedAt, style: .relative)")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack { FamilyView() }
}
