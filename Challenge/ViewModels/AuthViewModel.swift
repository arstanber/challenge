import Foundation
import AuthenticationServices
import Observation

@Observable
final class AuthViewModel {
    var email = ""
    var password = ""
    var confirmPassword = ""
    var isSignUp = false
    var isLoading = false
    var errorMessage: String?

    private let authService = AuthService.shared

    var isValid: Bool {
        if isSignUp {
            return !email.isEmpty && password.count >= 6 && password == confirmPassword
        }
        return !email.isEmpty && !password.isEmpty
    }

    func submit() async {
        guard isValid else { return }
        isLoading = true
        errorMessage = nil
        let normalizedEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        do {
            if isSignUp {
                try await authService.signUp(email: normalizedEmail, password: password)
            } else {
                try await authService.signIn(email: normalizedEmail, password: password)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func signInWithApple() async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await AppleSignInCoordinator.shared.signIn()
            try await authService.signInWithApple(credential: result.credential, nonce: result.nonce)
        } catch {
            // Ignore user cancellation.
            if (error as? ASAuthorizationError)?.code != .canceled {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }

    func handleGoogleSignIn() async {
        isLoading = true
        errorMessage = nil
        do {
            try await authService.signInWithGoogle()
        } catch {
            // Ignore user-initiated cancellation (GIDSignInError.canceled).
            let nsError = error as NSError
            let isCanceled = nsError.domain == "com.google.GIDSignIn" && nsError.code == -5
            if !isCanceled {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
    }
}
