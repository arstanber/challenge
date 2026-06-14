import AuthenticationServices
import CryptoKit
import UIKit

/// Drives Sign in with Apple programmatically (reliable taps) and produces the
/// raw nonce required by Supabase `signInWithIdToken`.
@MainActor
final class AppleSignInCoordinator: NSObject,
    ASAuthorizationControllerDelegate,
    ASAuthorizationControllerPresentationContextProviding {

    static let shared = AppleSignInCoordinator()

    struct Result {
        let credential: ASAuthorizationAppleIDCredential
        let nonce: String
    }

    private var continuation: CheckedContinuation<Result, Error>?
    private var currentNonce: String?

    /// Presents the Apple sheet and returns the credential + raw nonce.
    func signIn() async throws -> Result {
        // Guard against overlapping requests.
        if continuation != nil {
            throw NSError(domain: "AppleSignIn", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Sign in already in progress"])
        }
        let nonce = Self.randomNonceString()
        currentNonce = nonce

        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = Self.sha256(nonce)

        return try await withCheckedThrowingContinuation { cont in
            self.continuation = cont
            let controller = ASAuthorizationController(authorizationRequests: [request])
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    // MARK: - Delegate

    func authorizationController(controller: ASAuthorizationController,
                                didCompleteWithAuthorization authorization: ASAuthorization) {
        defer { continuation = nil; currentNonce = nil }
        guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let nonce = currentNonce else {
            continuation?.resume(throwing: NSError(domain: "AppleSignIn", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Invalid Apple credential"]))
            return
        }
        continuation?.resume(returning: Result(credential: credential, nonce: nonce))
    }

    func authorizationController(controller: ASAuthorizationController,
                                didCompleteWithError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
        currentNonce = nil
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
        // The anchor is only requested while the UI is on screen, so a window
        // is always available here.
        guard let window = windows.first(where: { $0.isKeyWindow }) ?? windows.first else {
            preconditionFailure("No window available to present Sign in with Apple")
        }
        return window
    }

    // MARK: - Nonce helpers

    private static func randomNonceString(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var random: UInt8 = 0
            _ = SecRandomCopyBytes(kSecRandomDefault, 1, &random)
            if random < charset.count {
                result.append(charset[Int(random)])
                remaining -= 1
            }
        }
        return result
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
