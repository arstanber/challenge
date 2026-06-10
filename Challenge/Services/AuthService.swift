import Foundation
import Supabase
import PostgREST
import AuthenticationServices
import Observation
#if canImport(UIKit)
import UIKit
#endif
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

enum AuthError: LocalizedError {
    case invalidCredentials
    case emailAlreadyInUse
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .invalidCredentials: return "Invalid email or password"
        case .emailAlreadyInUse: return "This email is already registered"
        case .unknown(let e): return e.localizedDescription
        }
    }
}

@Observable
final class AuthService {
    static let shared = AuthService()

    var currentUser: AppUser?
    var isAuthenticated = false
    /// True while the app is restoring the saved session on cold launch.
    var isRestoring = true

    private init() {
        Task { await restoreSession() }
    }

    // MARK: - Session Restore

    /// Minimum time the branded loading screen stays up on launch.
    private let minimumSplashDuration: TimeInterval = 3.0

    private func restoreSession() async {
        let start = Date()
        do {
            let session = try await supabase.auth.session
            try await loadUserProfile(id: session.user.id)
        } catch {
            isAuthenticated = false
        }
        // Keep the loading screen visible for at least `minimumSplashDuration`.
        let elapsed = Date().timeIntervalSince(start)
        if elapsed < minimumSplashDuration {
            try? await Task.sleep(nanoseconds: UInt64((minimumSplashDuration - elapsed) * 1_000_000_000))
        }
        isRestoring = false
    }

    private func loadUserProfile(id: UUID) async throws {
        let user: AppUser = try await supabase
            .from("users")
            .select()
            .eq("id", value: id.uuidString)
            .single()
            .execute()
            .value
        currentUser = user
        isAuthenticated = true
    }

    // MARK: - Auth Operations

    func signIn(email: String, password: String) async throws {
        do {
            let session = try await supabase.auth.signIn(email: email, password: password)
            try await loadUserProfile(id: session.user.id)
            AnalyticsService.shared.track(.signedIn, ["method": "email"])
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.unknown(error)
        }
    }

    func signUp(email: String, password: String) async throws {
        do {
            let response = try await supabase.auth.signUp(email: email, password: password)
            let user = response.user

            let profile = AppUserInsert(
                id: user.id,
                email: email,
                plan: .free,
                role: .individual
            )
            let inserted: AppUser = try await supabase
                .from("users")
                .insert(profile)
                .select()
                .single()
                .execute()
                .value
            currentUser = inserted
            isAuthenticated = true
            AnalyticsService.shared.track(.signedUp, ["method": "email"])
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.unknown(error)
        }
    }

    func signInWithApple(credential: ASAuthorizationAppleIDCredential, nonce: String) async throws {
        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            throw AuthError.unknown(NSError(domain: "AppleAuth", code: -1))
        }
        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken, nonce: nonce)
            )
            // Try to load existing profile, create if missing
            do {
                try await loadUserProfile(id: session.user.id)
                AnalyticsService.shared.track(.signedIn, ["method": "apple"])
            } catch {
                let email = credential.email ?? session.user.email ?? ""
                let profile = AppUserInsert(
                    id: session.user.id,
                    email: email,
                    plan: .free,
                    role: .individual
                )
                let inserted: AppUser = try await supabase
                    .from("users")
                    .insert(profile)
                    .select()
                    .single()
                    .execute()
                    .value
                currentUser = inserted
                isAuthenticated = true
                AnalyticsService.shared.track(.signedUp, ["method": "apple"])
            }
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.unknown(error)
        }
    }

    func signInWithGoogle() async throws {
        #if canImport(GoogleSignIn)
        let tokens = try await Self.presentGoogleSignIn()
        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: .init(provider: .google, idToken: tokens.idToken, accessToken: tokens.accessToken)
            )
            // Try to load existing profile, create if missing
            do {
                try await loadUserProfile(id: session.user.id)
                AnalyticsService.shared.track(.signedIn, ["method": "google"])
            } catch {
                let email = tokens.email.isEmpty ? (session.user.email ?? "") : tokens.email
                let profile = AppUserInsert(
                    id: session.user.id,
                    email: email,
                    plan: .free,
                    role: .individual
                )
                let inserted: AppUser = try await supabase
                    .from("users")
                    .insert(profile)
                    .select()
                    .single()
                    .execute()
                    .value
                currentUser = inserted
                isAuthenticated = true
                AnalyticsService.shared.track(.signedUp, ["method": "google"])
            }
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.unknown(error)
        }
        #else
        throw AuthError.unknown(NSError(domain: "GoogleAuth", code: -1))
        #endif
    }

    func signOut() {
        Task {
            try? await supabase.auth.signOut()
            currentUser = nil
            isAuthenticated = false
            AnalyticsService.shared.track(.signedOut)
        }
    }

    #if canImport(GoogleSignIn)
    @MainActor
    private static func presentGoogleSignIn() async throws -> (idToken: String, accessToken: String, email: String) {
        guard let rootVC = UIApplication.shared.topViewController else {
            throw AuthError.unknown(NSError(
                domain: "GoogleAuth", code: -2,
                userInfo: [NSLocalizedDescriptionKey: "No view controller available to present sign-in"]
            ))
        }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
        guard let idToken = result.user.idToken?.tokenString else {
            throw AuthError.unknown(NSError(
                domain: "GoogleAuth", code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Missing Google ID token"]
            ))
        }
        return (idToken, result.user.accessToken.tokenString, result.user.profile?.email ?? "")
    }
    #endif
}

#if canImport(UIKit)
extension UIApplication {
    /// The top-most presented view controller, used as the anchor for system sign-in sheets.
    var topViewController: UIViewController? {
        let root = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }?
            .rootViewController
        var top = root
        while let presented = top?.presentedViewController {
            top = presented
        }
        return top
    }
}
#endif

// Insert-only model without server-generated fields
struct AppUserInsert: Encodable {
    let id: UUID
    let email: String
    let plan: UserPlan
    let role: UserRole
}
