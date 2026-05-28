import SwiftUI
import AuthenticationServices

struct AuthView: View {
    @State private var vm = AuthViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 28) {
                    VStack(spacing: 12) {
                        Image(systemName: "flame.circle.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(.orange)
                        Text("Challenge")
                            .font(.largeTitle.bold())
                        Text(vm.isSignUp ? "Create your account" : "Welcome back")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 40)

                    VStack(spacing: 14) {
                        TextField("Email", text: $vm.email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .padding(14)
                            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))

                        SecureField("Password", text: $vm.password)
                            .padding(14)
                            .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))

                        if vm.isSignUp {
                            SecureField("Confirm password", text: $vm.confirmPassword)
                                .padding(14)
                                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
                        }
                    }

                    if let error = vm.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                    }

                    Button {
                        Task { await vm.submit() }
                    } label: {
                        Group {
                            if vm.isLoading {
                                ProgressView().tint(.white)
                            } else {
                                Text(vm.isSignUp ? "Create account" : "Sign in")
                                    .fontWeight(.semibold)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.orange)
                    .disabled(!vm.isValid || vm.isLoading)

                    HStack {
                        Rectangle().fill(.separator).frame(height: 1)
                        Text("or")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                        Rectangle().fill(.separator).frame(height: 1)
                    }

                    SignInWithAppleButton(vm.isSignUp ? .signUp : .signIn) { request in
                        request.requestedScopes = [.fullName, .email]
                    } onCompletion: { result in
                        Task { await vm.handleAppleSignIn(result) }
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 50)
                    .cornerRadius(10)

                    Button {
                        withAnimation { vm.isSignUp.toggle() }
                        vm.errorMessage = nil
                    } label: {
                        Text(vm.isSignUp ? "Already have an account? **Sign in**" : "New here? **Create account**")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 40)
            }
        }
    }
}

#Preview {
    AuthView()
}
