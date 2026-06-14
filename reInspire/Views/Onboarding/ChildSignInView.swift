import SwiftUI

/// Sign-in screen for parent-provisioned child accounts (login code + PIN).
struct ChildSignInView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AuthService.self) private var authService
    @State private var vm = AuthViewModel()
    @FocusState private var pinFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "figure.child.circle.fill")
                            .font(.system(size: 40)).foregroundStyle(.purple)
                        Text("Войди данными, которые дал родитель.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
                Section("Логин") {
                    TextField("Например, AB12CD", text: $vm.childLoginCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                }
                Section("PIN") {
                    SecureField("PIN", text: $vm.childPin)
                        .keyboardType(.numberPad)
                        .focused($pinFocused)
                        .onChange(of: vm.childPin) { _, new in
                            vm.childPin = String(new.filter(\.isNumber).prefix(6))
                        }
                }
                if let error = vm.errorMessage {
                    Section { Text(error).font(.caption).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Войти как ребёнок")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Войти") {
                        Task { await vm.signInChild() }
                    }
                    .fontWeight(.semibold)
                    .disabled(!vm.isChildValid || vm.isLoading)
                    .overlay { if vm.isLoading { ProgressView().scaleEffect(0.7) } }
                }
            }
            .onChange(of: authService.isAuthenticated) { _, isAuth in
                if isAuth { dismiss() }
            }
        }
    }
}
