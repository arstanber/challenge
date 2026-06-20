import SwiftUI

struct FamilyView: View {
    @Environment(AuthService.self) private var auth
    @State private var vm = ProfileViewModel()
    @State private var joinCode = ""
    @State private var showLeave = false
    @State private var showDelete = false
    @State private var memberToRemove: FamilyMember?

    // Sheets
    @State private var showCreateChild = false
    @State private var showNearby = false
    @State private var assignTaskMember: FamilyMember?
    @State private var credentialsMember: FamilyMember?
    @State private var showAssignAll = false

    // Child code-gated leave
    @State private var showLeaveCodeEntry = false
    @State private var leaveCode = ""

    private var role: UserRole { vm.user?.role ?? .individual }

    var body: some View {
        List {
            switch role {
            case .parent:     parentSections
            case .child:      childSection
            case .individual: setupSection
            }
        }
        .navigationTitle("Семья")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await vm.loadProfile() }
        .task { await vm.loadProfile() }
        .sheet(isPresented: $showCreateChild) { CreateChildSheet(vm: vm) }
        .sheet(isPresented: $showNearby) {
            NearbyConnectView(myCode: vm.family?.inviteCode) { await vm.loadProfile() }
        }
        .sheet(item: $assignTaskMember) { member in
            CreateActivityView(presetChildId: member.childUserId,
                               presetChildName: member.childUser?.displayLabel)
        }
        .sheet(isPresented: $showAssignAll) {
            CreateActivityView(presetChildIds: vm.kidUserIds,
                               presetChildName: "всех детей")
        }
        .sheet(item: $credentialsMember) { member in
            ChildCredentialsSheet(vm: vm, member: member)
        }
        .sheet(item: Binding(get: { vm.lastCreatedChild }, set: { vm.lastCreatedChild = $0 })) { child in
            ChildCreatedSheet(child: child)
        }
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
        .alert("Подтверди выход", isPresented: $showLeaveCodeEntry) {
            TextField("Код от родителя", text: $leaveCode)
                .keyboardType(.numberPad)
            Button("Выйти", role: .destructive) {
                let code = leaveCode
                leaveCode = ""
                Task {
                    if await vm.leaveFamilyWithCode(code) { Haptics.success() }
                }
            }
            Button("Отмена", role: .cancel) { leaveCode = "" }
        } message: {
            Text("Родитель получил код. Введи его, чтобы выйти из семьи.")
        }
    }

    // MARK: Parent

    @ViewBuilder private var parentSections: some View {
        if let family = vm.family {
            Section("Приглашение") {
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
                if let text = vm.inviteShareText {
                    ShareLink(item: text) {
                        Label("Поделиться ссылкой", systemImage: "square.and.arrow.up")
                    }
                }
                Button {
                    Haptics.tap(); showNearby = true
                } label: {
                    Label("Соединить рядом (потрясти телефоны)", systemImage: "wave.3.right")
                }
                Text("Поделись кодом или ссылкой, либо потрясите два телефона рядом, чтобы добавить ребёнка.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }

        Section("Ты") {
            HStack {
                Image(systemName: (vm.user?.familyRole ?? .dad).icon).foregroundStyle(.purple)
                Text(vm.user?.displayLabel ?? "Родитель").font(.subheadline.bold())
                Spacer()
                Menu {
                    Button { Task { await vm.setMyFamilyRole(.mom) } } label: { Label("Мама", systemImage: "figure.dress") }
                    Button { Task { await vm.setMyFamilyRole(.dad) } } label: { Label("Папа", systemImage: "figure") }
                } label: {
                    Text((vm.user?.familyRole ?? .dad).title)
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 5)
                        .background(Capsule().fill(Color.purple.opacity(0.12)))
                        .foregroundStyle(.purple)
                }
            }
        }

        Section("Аккаунты детей") {
            Button {
                Haptics.tap(); showCreateChild = true
            } label: {
                Label("Создать аккаунт ребёнку", systemImage: "person.badge.plus")
            }
            if !vm.kids.isEmpty {
                Button {
                    Haptics.tap(); showAssignAll = true
                } label: {
                    Label("Дать задание всем детям", systemImage: "checklist")
                }
            }
            Text("Заведи ребёнку логин и PIN -- он войдёт на своём телефоне этими данными. Можно дать задание одному ребёнку (свайп влево по нему) или сразу всем.")
                .font(.caption).foregroundStyle(.secondary)
        }

        if !vm.leaveRequests.isEmpty {
            Section("Запросы на выход") {
                ForEach(vm.leaveRequests) { req in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(req.childName).font(.subheadline.bold())
                            Text("хочет выйти из семьи")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(req.code)
                            .font(.title3.bold().monospaced())
                            .foregroundStyle(.orange)
                            .onTapGesture { UIPasteboard.general.string = req.code; Haptics.success() }
                    }
                }
                Text("Сообщи код ребёнку, только если согласен отпустить его из семьи.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }

        roleGroup(title: "Мамы", members: vm.moms)
        roleGroup(title: "Папы", members: vm.dads)
        roleGroup(title: "Дети (\(vm.kids.count))", members: vm.kids, isKids: true)

        if !vm.kids.isEmpty {
            assignmentsSection
        }

        Section {
            Button(role: .destructive) { Haptics.warning(); showDelete = true } label: {
                Text("Удалить семью")
            }
        }
    }

    @ViewBuilder private func roleGroup(title: String, members: [FamilyMember], isKids: Bool = false) -> some View {
        if !members.isEmpty {
            Section(title) {
                ForEach(members) { member in
                    memberRow(member)
                        .swipeActions(edge: .leading) {
                            if isKids {
                                Button { assignTaskMember = member } label: {
                                    Label("Задание", systemImage: "plus.circle")
                                }.tint(.purple)
                                Button { credentialsMember = member } label: {
                                    Label("Вход", systemImage: "key")
                                }.tint(.blue)
                            }
                        }
                        .swipeActions {
                            Button(role: .destructive) { memberToRemove = member } label: {
                                Label("Убрать", systemImage: "person.fill.xmark")
                            }
                        }
                }
            }
        } else if isKids {
            Section(title) {
                Text("Пока нет детей. Создай аккаунт или пригласи по коду.")
                    .font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Assignments (who completed what)

    @ViewBuilder private var assignmentsSection: some View {
        Section("Задания") {
            if vm.assignments.isEmpty {
                Text("Пока нет заданий. Дай задание ребёнку (свайп влево по нему) или сразу всем.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(vm.assignments) { assignment in
                    NavigationLink {
                        AssignmentDetailView(assignment: assignment)
                    } label: {
                        assignmentRow(assignment)
                    }
                }
            }
        }
    }

    private func assignmentRow(_ a: AssignmentOverview) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(a.title).font(.subheadline.bold()).lineLimit(1)
                if let deadline = a.deadline {
                    Label(Self.deadlineFormatter.string(from: deadline), systemImage: "calendar")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Text("\(a.doneCount)/\(a.total)")
                .font(.caption.bold().monospacedDigit())
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(
                    (a.doneCount == a.total ? Color.green : Color.orange).opacity(0.15)))
                .foregroundStyle(a.doneCount == a.total ? .green : .orange)
        }
        .padding(.vertical, 2)
    }

    static let deadlineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM"
        return f
    }()

    // MARK: Child

    @ViewBuilder private var childSection: some View {
        Section {
            HStack(spacing: 12) {
                UserAvatarView(urlString: vm.user?.avatarURL,
                               label: vm.user?.displayLabel ?? "Ты",
                               size: 40, tint: .purple)
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.user?.displayLabel ?? "Ты")
                        .font(.subheadline.bold())
                    Text("Ты в семейной группе")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }

        if !vm.memberParents.isEmpty {
            Section("Родители") {
                ForEach(vm.memberParents) { member in childMemberRow(member) }
            }
        }
        Section("Дети (\(vm.memberKids.count))") {
            if vm.memberKids.isEmpty {
                Text("Других детей пока нет.")
                    .font(.subheadline).foregroundStyle(.secondary)
            } else {
                ForEach(vm.memberKids) { member in childMemberRow(member) }
            }
        }

        Section {
            Button(role: .destructive) {
                Haptics.warning()
                Task { if await vm.requestLeaveCode() { showLeaveCodeEntry = true } }
            } label: {
                HStack {
                    Text("Покинуть семью")
                    if vm.isLoading { Spacer(); ProgressView().scaleEffect(0.7) }
                }
            }
            .disabled(vm.isLoading)
            Text("Выйти из семьи можно только с кодом, который придёт родителю. Запроси код и попроси его у родителя.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    /// Read-only roster row for the child's view of the family.
    private func childMemberRow(_ member: AppUser) -> some View {
        let role = member.familyRole ?? .child
        return HStack(spacing: 12) {
            UserAvatarView(urlString: member.avatarURL, label: member.displayLabel,
                           size: 36, tint: .purple)
            VStack(alignment: .leading, spacing: 2) {
                Text(member.displayLabel).font(.subheadline.bold())
                Text(role.title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if member.id == vm.user?.id {
                Text("ты").font(.caption2.bold()).foregroundStyle(.purple)
            }
        }
        .padding(.vertical, 2)
    }

    // MARK: Individual (setup)

    @ViewBuilder private var setupSection: some View {
        Section("Создать семью") {
            Text("Создай семейную группу, чтобы заводить детям аккаунты, давать задания и видеть их рейтинг.")
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
            Button {
                Haptics.tap(); showNearby = true
            } label: {
                Label("Соединить рядом (потрясти телефоны)", systemImage: "wave.3.right")
            }
        }

        if let error = vm.errorMessage {
            Section { Text(error).font(.caption).foregroundStyle(.red) }
        }
    }

    private func memberRow(_ member: FamilyMember) -> some View {
        let currentRole = member.childUser?.familyRole ?? .child
        return HStack {
            Circle()
                .fill(.purple.opacity(0.2))
                .frame(width: 36, height: 36)
                .overlay { Image(systemName: currentRole.icon).foregroundStyle(.purple) }
            VStack(alignment: .leading, spacing: 2) {
                Text(member.childUser?.displayLabel ?? "Участник")
                    .font(.subheadline.bold())
                if let code = member.childUser?.childLoginCode {
                    Text("Логин: \(code)")
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                } else {
                    Text("Присоединился \(member.joinedAt, style: .relative)")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            Menu {
                ForEach(FamilyRole.allCases) { r in
                    Button {
                        Task { await vm.setFamilyRole(member, to: r) }
                    } label: {
                        Label(r.title, systemImage: currentRole == r ? "checkmark" : r.icon)
                    }
                }
            } label: {
                Text(currentRole.title)
                    .font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(Capsule().fill(Color.purple.opacity(0.12)))
                    .foregroundStyle(.purple)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Create child sheet

private struct CreateChildSheet: View {
    @Bindable var vm: ProfileViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var pin = ""

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && (4...6).contains(pin.count) && pin.allSatisfy(\.isNumber)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Имя ребёнка") {
                    TextField("Например, Маша", text: $name)
                        .autocorrectionDisabled()
                }
                Section("PIN (4-6 цифр)") {
                    SecureField("PIN", text: $pin)
                        .keyboardType(.numberPad)
                        .onChange(of: pin) { _, new in
                            pin = String(new.filter(\.isNumber).prefix(6))
                        }
                }
                Section {
                    Text("Ребёнок войдёт на своём телефоне по логину (мы его выдадим) и этому PIN. Запиши PIN -- восстановить его нельзя, только пересоздать аккаунт.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = vm.errorMessage {
                    Section { Text(error).font(.caption).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Аккаунт ребёнка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") {
                        Task {
                            let ok = await vm.createChild(name: name, pin: pin)
                            if ok { Haptics.success(); dismiss() }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid || vm.isLoading)
                    .overlay { if vm.isLoading { ProgressView().scaleEffect(0.7) } }
                }
            }
        }
    }
}

// MARK: - Child created (hand-off card)

private struct ChildCreatedSheet: View {
    let child: ProfileViewModel.CreatedChild
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 56)).foregroundStyle(.green)
                    .padding(.top, 20)
                Text("Аккаунт для \(child.name) готов")
                    .font(.title3.bold()).multilineTextAlignment(.center)
                Text("Передай эти данные ребёнку -- он войдёт на своём телефоне через «Войти как ребёнок».")
                    .font(.subheadline).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).padding(.horizontal)

                VStack(spacing: 12) {
                    credRow(title: "Логин", value: child.loginCode)
                    credRow(title: "PIN", value: child.pin)
                }
                .padding(.horizontal)

                ShareLink(item: "Войди в reInspire как ребёнок:\nЛогин: \(child.loginCode)\nPIN: \(child.pin)") {
                    Label("Поделиться данными", systemImage: "square.and.arrow.up")
                }
                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { dismiss() }.fontWeight(.semibold)
                }
            }
        }
    }

    private func credRow(title: String, value: String) -> some View {
        HStack {
            Text(title).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.title3.bold().monospaced()).foregroundStyle(.purple)
            Button {
                UIPasteboard.general.string = value; Haptics.success()
            } label: { Image(systemName: "doc.on.doc") }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.purple.opacity(0.08)))
    }
}

// MARK: - Change child credentials (parent)

private struct ChildCredentialsSheet: View {
    @Bindable var vm: ProfileViewModel
    let member: FamilyMember
    @Environment(\.dismiss) private var dismiss
    @State private var email = ""
    @State private var password = ""

    private var isValid: Bool {
        email.contains("@") && email.contains(".") && password.count >= 6
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Измени почту и пароль для \(member.childUser?.displayLabel ?? "ребёнка"). Этими данными ребёнок входит в приложение.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                Section("Почта") {
                    TextField("you@example.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Новый пароль (от 6 символов)") {
                    SecureField("Пароль", text: $password)
                }
                if let error = vm.errorMessage {
                    Section { Text(error).font(.caption).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Вход ребёнка")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") {
                        Task {
                            let ok = await vm.setChildCredentials(
                                childId: member.childUserId, email: email, password: password)
                            if ok { Haptics.success(); dismiss() }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!isValid || vm.isLoading)
                    .overlay { if vm.isLoading { ProgressView().scaleEffect(0.7) } }
                }
            }
        }
    }
}

// MARK: - Assignment detail (per-child completion)

private struct AssignmentDetailView: View {
    let assignment: AssignmentOverview

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Text(assignment.title).font(.headline)
                    if !assignment.description.isEmpty {
                        Text(assignment.description)
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if let deadline = assignment.deadline {
                        Label("Дедлайн: \(FamilyView.deadlineFormatter.string(from: deadline))",
                              systemImage: "calendar")
                            .font(.caption.bold()).foregroundStyle(.purple)
                    }
                    Text("Выполнили \(assignment.doneCount) из \(assignment.total)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("Кто выполнил") {
                ForEach(assignment.children) { child in
                    HStack(spacing: 12) {
                        UserAvatarView(urlString: child.avatarURL, label: child.name,
                                       size: 36, tint: .purple)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(child.name).font(.subheadline.bold())
                            if let at = child.lastReportAt, child.state != .waiting {
                                Text(at, style: .relative)
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Label(child.state.title, systemImage: child.state.icon)
                            .font(.caption.bold())
                            .foregroundStyle(Self.color(for: child.state))
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Задание")
        .navigationBarTitleDisplayMode(.inline)
    }

    private static func color(for state: AssignmentChildState) -> Color {
        switch state {
        case .done:     return .green
        case .pending:  return .orange
        case .rejected: return .red
        case .waiting:  return .secondary
        }
    }
}

#Preview {
    NavigationStack { FamilyView().environment(AuthService.shared) }
}
