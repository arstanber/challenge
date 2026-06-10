import SwiftUI

struct FamilyView: View {
    @State private var vm = ProfileViewModel()

    var body: some View {
        List {
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
                        HStack {
                            Circle()
                                .fill(.purple.opacity(0.2))
                                .frame(width: 36, height: 36)
                                .overlay {
                                    Image(systemName: "person.fill").foregroundStyle(.purple)
                                }
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
            }
        }
        .navigationTitle("Семья")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await vm.loadProfile() }
        .task { await vm.loadProfile() }
    }
}

#Preview {
    NavigationStack { FamilyView() }
}
