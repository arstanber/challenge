import Foundation
import Supabase
import PostgREST
import AuthenticationServices
import Observation

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

    private init() {
        Task { await restoreSession() }
    }

    // MARK: - Session Restore

    private func restoreSession() async {
        do {
            let session = try await supabase.auth.session
            try await loadUserProfile(id: session.user.id)
        } catch {
            isAuthenticated = false
        }
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
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.unknown(error)
        }
    }

    func signInWithApple(credential: ASAuthorizationAppleIDCredential) async throws {
        guard let tokenData = credential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8) else {
            throw AuthError.unknown(NSError(domain: "AppleAuth", code: -1))
        }
        do {
            let session = try await supabase.auth.signInWithIdToken(
                credentials: .init(provider: .apple, idToken: idToken)
            )
            // Try to load existing profile, create if missing
            do {
                try await loadUserProfile(id: session.user.id)
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
            }
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.unknown(error)
        }
    }

    func signOut() {
        Task {
            try? await supabase.auth.signOut()
            currentUser = nil
            isAuthenticated = false
        }
    }
}

// Insert-only model without server-generated fields
struct AppUserInsert: Encodable {
    let id: UUID
    let email: String
    let plan: UserPlan
    let role: UserRole
}
