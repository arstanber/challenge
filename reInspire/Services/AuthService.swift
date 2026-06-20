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
import os.log

private let authLogger = Logger(subsystem: "com.reinspire", category: "AuthService")
private let welcomeIntroKey = "needsWelcomeIntro"

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
    /// Family invite code captured from a deep link (reinspire://join?code=...)
    /// or a shake pairing while signed out -- consumed once the user is signed in.
    var pendingFamilyCode: String? {
        didSet { UserDefaults.standard.set(pendingFamilyCode, forKey: "pendingFamilyCode") }
    }
    /// Set right after account creation; RootView shows WeekOnUsView once and
    /// clears it. Persisted so a force-quit on the intro doesn't skip it.
    /// Signing in to an existing account resets it (session restore does not).
    var needsWelcomeIntro = UserDefaults.standard.bool(forKey: welcomeIntroKey) {
        didSet { UserDefaults.standard.set(needsWelcomeIntro, forKey: welcomeIntroKey) }
    }

    private init() {
        pendingFamilyCode = UserDefaults.standard.string(forKey: "pendingFamilyCode")
        Task { await restoreSession() }
    }

    // MARK: - Child accounts (parent-provisioned name + PIN)

    /// Synthetic auth credentials for a parent-created child account. Must match
    /// the derivation in the `create-child` edge function exactly.
    static func kidCredentials(loginCode: String, pin: String) -> (email: String, password: String) {
        let code = loginCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let email = "kid.\(code.lowercased())@kids.thechallenges.app"
        let password = "\(code):\(pin.trimmingCharacters(in: .whitespacesAndNewlines))"
        return (email, password)
    }

    /// Sign a child in with the login code their parent gave them + the PIN.
    func signInChild(loginCode: String, pin: String) async throws {
        let creds = Self.kidCredentials(loginCode: loginCode, pin: pin)
        do {
            let session = try await supabase.auth.signIn(email: creds.email, password: creds.password)
            try await loadUserProfile(id: session.user.id)
            needsWelcomeIntro = false
            AnalyticsService.shared.track(.signedIn, ["method": "child"])
        } catch {
            throw AuthError.invalidCredentials
        }
    }

    /// A signed-in child sets their own real email + password (forced on first
    /// sign-in). Goes through the `set-child-credentials` edge function, which
    /// updates the auth user with the admin API (no email confirmation needed),
    /// then we re-pull the profile so `needsChildCredentials` clears.
    func setOwnChildCredentials(email: String, password: String) async throws {
        struct Req: Encodable { let email: String; let password: String }
        struct Ack: Decodable { let ok: Bool? }
        let normalized = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let _: Ack = try await supabase.functions.invoke(
            "set-child-credentials",
            options: FunctionInvokeOptions(body: Req(email: normalized, password: password))
        )
        await refreshProfile()
        AnalyticsService.shared.track(.signedUp, ["method": "child_upgrade"])
    }

    /// Change the signed-in user's password.
    /// Sends a one-time confirmation code to the signed-in user's email so a
    /// password change can be reauthenticated. Call before ``changePassword``.
    func sendPasswordChangeCode() async throws {
        try await supabase.auth.reauthenticate()
    }

    /// Changes the password, gated by the reauthentication code emailed via
    /// ``sendPasswordChangeCode``. The `nonce` is the code the user entered.
    func changePassword(to newPassword: String, nonce: String) async throws {
        let code = nonce.trimmingCharacters(in: .whitespacesAndNewlines)
        try await supabase.auth.update(user: UserAttributes(password: newPassword, nonce: code))
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
        syncTimezone(userId: id)
    }

    /// Re-pull the users row; plan, pro_until and bonus_freezes change
    /// server-side (referral rewards, plan grants).
    func refreshProfile() async {
        guard let id = currentUser?.id else { return }
        try? await loadUserProfile(id: id)
    }

    /// Fire-and-forget upsert of the device timezone -- the server uses it for
    /// streak day-bucketing and reminder scheduling (users.timezone).
    func syncTimezone(userId: UUID) {
        Task {
            do {
                try await supabase
                    .from("users")
                    .update(["timezone": TimeZone.current.identifier])
                    .eq("id", value: userId.uuidString)
                    .execute()
            } catch {
                authLogger.error("timezone sync failed: \(error)")
            }
        }
    }

    // MARK: - Auth Operations

    func signIn(email: String, password: String) async throws {
        do {
            let session = try await supabase.auth.signIn(email: email, password: password)
            do {
                try await loadUserProfile(id: session.user.id)
                needsWelcomeIntro = false
            } catch let pgErr as PostgrestError where pgErr.code == "PGRST116" {
                // PGRST116 = no profile row. The auth user exists and is
                // confirmed, but the in-app profile-create step never ran --
                // e.g. the email was confirmed via the link in the browser
                // instead of the code screen. Create the profile now that we
                // hold a session, so the account isn't permanently stuck.
                let profile = AppUserInsert(
                    id: session.user.id,
                    email: session.user.email ?? email,
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
                syncTimezone(userId: inserted.id)
                needsWelcomeIntro = true
            }
            AnalyticsService.shared.track(.signedIn, ["method": "email"])
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.unknown(error)
        }
    }

    /// Step 1 of email sign-up. Creates the auth user; with email confirmation
    /// enabled this returns NO session and Supabase emails a 6-digit code. The
    /// `users` profile row is created only after the code is verified
    /// (`confirmSignUp`), because the RLS insert policy requires an
    /// authenticated session (`auth.uid() = id`).
    /// Returns `true` if the user was auto-confirmed -- i.e. "Confirm email" is
    /// disabled in Supabase, so signUp returned a live session and NO code was
    /// emailed. The caller must then skip the code screen, otherwise the user
    /// waits forever for a code that will never arrive. Returns `false` when a
    /// code was emailed and confirmation is still pending.
    @discardableResult
    func signUp(email: String, password: String) async throws -> Bool {
        do {
            let response = try await supabase.auth.signUp(email: email, password: password)
            guard response.session != nil else { return false }
            // Auto-confirmed: establish the profile now, same as confirmSignUp.
            do {
                try await loadUserProfile(id: response.user.id)
            } catch let pgErr as PostgrestError where pgErr.code == "PGRST116" {
                let profile = AppUserInsert(
                    id: response.user.id,
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
                syncTimezone(userId: inserted.id)
            }
            needsWelcomeIntro = true
            AnalyticsService.shared.track(.signedUp, ["method": "email"])
            return true
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.unknown(error)
        }
    }

    /// Step 2 of email sign-up. Verifies the 6-digit code from the email, which
    /// establishes a session, then creates the profile row (idempotent: loads it
    /// if it somehow already exists).
    func confirmSignUp(email: String, code: String) async throws {
        do {
            let token = code.trimmingCharacters(in: .whitespacesAndNewlines)
            let response = try await supabase.auth.verifyOTP(
                email: email, token: token, type: .signup
            )
            let userId = response.user.id
            do {
                // Verified existing profile (e.g. a retried confirmation).
                try await loadUserProfile(id: userId)
            } catch let pgErr as PostgrestError where pgErr.code == "PGRST116" {
                // PGRST116 = no rows => brand-new user, create the profile now
                // that we hold a session.
                let profile = AppUserInsert(
                    id: userId,
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
                syncTimezone(userId: inserted.id)
            }
            needsWelcomeIntro = true
            AnalyticsService.shared.track(.signedUp, ["method": "email"])
        } catch let error as AuthError {
            throw error
        } catch {
            throw AuthError.unknown(error)
        }
    }

    /// Re-sends the sign-up confirmation code to the email.
    func resendSignUpCode(email: String) async throws {
        try await supabase.auth.resend(email: email, type: .signup)
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
                needsWelcomeIntro = false
                AnalyticsService.shared.track(.signedIn, ["method": "apple"])
            } catch let pgErr as PostgrestError where pgErr.code == "PGRST116" {
                // PGRST116 = .single() returned no rows => brand-new user.
                // Any other error (network, etc.) propagates instead of
                // spuriously creating a duplicate profile.
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
                needsWelcomeIntro = true
                isAuthenticated = true
                syncTimezone(userId: inserted.id)
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
                needsWelcomeIntro = false
                AnalyticsService.shared.track(.signedIn, ["method": "google"])
            } catch let pgErr as PostgrestError where pgErr.code == "PGRST116" {
                // PGRST116 = .single() returned no rows => brand-new user.
                // Any other error (network, etc.) propagates instead of
                // spuriously creating a duplicate profile.
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
                needsWelcomeIntro = true
                isAuthenticated = true
                syncTimezone(userId: inserted.id)
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
