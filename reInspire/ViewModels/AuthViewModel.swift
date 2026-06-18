import Foundation
import AuthenticationServices
import Observation

@Observable
@MainActor
final class AuthViewModel {
    var email = ""
    var password = ""
    var confirmPassword = ""
    var isSignUp = false
    var isLoading = false
    var errorMessage: String?

    // Email confirmation (6-digit code) -- shown after a successful sign-up.
    var awaitingCode = false
    var pendingEmail = ""
    var code = ""

    // Child sign-in (login code + PIN)
    var childLoginCode = ""
    var childPin = ""

    private let authService = AuthService.shared

    var isCodeValid: Bool {
        code.trimmingCharacters(in: .whitespaces).count == 6
    }

    var isChildValid: Bool {
        childLoginCode.trimmingCharacters(in: .whitespaces).count >= 4
            && (4...6).contains(childPin.trimmingCharacters(in: .whitespaces).count)
    }

    func signInChild() async {
        guard isChildValid else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await authService.signInChild(loginCode: childLoginCode, pin: childPin)
        } catch {
            errorMessage = "Неверный код или PIN"
        }
        isLoading = false
    }

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
                // No session yet -- a code was emailed. Move to code entry.
                pendingEmail = normalizedEmail
                code = ""
                awaitingCode = true
            } else {
                try await authService.signIn(email: normalizedEmail, password: password)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// Verify the 6-digit code from the confirmation email. On success the
    /// AuthService flips `isAuthenticated` and the onboarding completes.
    func verifyCode() async {
        guard isCodeValid else { return }
        isLoading = true
        errorMessage = nil
        do {
            try await authService.confirmSignUp(email: pendingEmail, code: code)
        } catch {
            errorMessage = "Неверный или просроченный код. Попробуйте ещё раз."
        }
        isLoading = false
    }

    /// Re-send the confirmation code to `pendingEmail`.
    func resendCode() async {
        errorMessage = nil
        do {
            try await authService.resendSignUpCode(email: pendingEmail)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Leave the code screen and return to the sign-in / sign-up form.
    func cancelCodeEntry() {
        awaitingCode = false
        code = ""
        errorMessage = nil
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
