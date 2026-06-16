import SwiftUI

/// Blocking screen shown to a parent-provisioned child the first time they sign
/// in. They must register a real email + password before using the app; the
/// synthetic kid login is replaced. Parents can change these later.
struct ChildSetCredentialsView: View {
    @Environment(AuthService.self) private var auth

    @State private var email = ""
    @State private var password = ""
    @State private var confirm = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focus: Field?

    private enum Field { case email, password, confirm }

    private var isValid: Bool {
        email.contains("@") && email.contains(".")
            && password.count >= 6 && password == confirm
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "envelope.badge.shield.half.filled")
                            .font(.system(size: 44)).foregroundStyle(.purple)
                        Text("Заверши настройку аккаунта")
                            .font(.title3.bold()).multilineTextAlignment(.center)
                        Text("Придумай почту и пароль -- ими ты будешь входить дальше. Родитель сможет их изменить.")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .listRowBackground(Color.clear)
                }
                Section("Почта") {
                    TextField("you@example.com", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .email)
                }
                Section("Пароль (от 6 символов)") {
                    SecureField("Пароль", text: $password)
                        .focused($focus, equals: .password)
                    SecureField("Повтори пароль", text: $confirm)
                        .focused($focus, equals: .confirm)
                }
                if let errorMessage {
                    Section { Text(errorMessage).font(.caption).foregroundStyle(.red) }
                }
                Section {
                    Button {
                        Task { await save() }
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading { ProgressView() } else { Text("Сохранить и войти").fontWeight(.semibold) }
                            Spacer()
                        }
                    }
                    .disabled(!isValid || isLoading)
                }
            }
            .navigationTitle("Регистрация")
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(true)
        }
    }

    private func save() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await auth.setOwnChildCredentials(email: email, password: password)
            Haptics.success()
        } catch {
            errorMessage = "Не удалось сохранить. Возможно, почта уже занята."
        }
    }
}

#Preview {
    ChildSetCredentialsView().environment(AuthService.shared)
}
