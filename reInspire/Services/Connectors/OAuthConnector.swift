import Foundation
import UIKit
import CryptoKit
import AuthenticationServices
import Supabase

/// OAuth2 web-API connectors (Strava, Whoop, Notion, Google Calendar/Docs/Drive/Gmail).
///
/// Flow:
/// 1. `ASWebAuthenticationSession` opens the provider's consent page.
/// 2. Provider redirects back to the app via a custom URL scheme with `?code=…`.
/// 3. We hand the `code` (plus the PKCE `code_verifier` for providers that use it) to the
///    `connector-oauth` Edge Function, which exchanges it for tokens **using the client
///    secret server-side** (when one is required) and stores them in `connector_tokens`.
///
/// The app never sees the client secret or the long-lived tokens.
final class OAuthConnector: NSObject, ASWebAuthenticationPresentationContextProviding {

    /// Retained for the duration of the web auth session (otherwise it deallocates mid-flow).
    private var webSession: ASWebAuthenticationSession?

    // MARK: - Connect

    func connect(_ provider: DataConnector) async throws {
        let cfg = OAuthConfig.config(for: provider)
        guard !cfg.clientId.hasPrefix("<") else {
            throw ConnectorError.notConfigured("\(provider.displayName): добавьте Client ID в OAuthConfig (см. CONNECTORS_SETUP.md).")
        }

        let pkce = cfg.usesPKCE ? PKCE.generate() : nil

        var comps = URLComponents(string: cfg.authorizeURL)
        var items = [
            URLQueryItem(name: "client_id", value: cfg.clientId),
            URLQueryItem(name: "redirect_uri", value: cfg.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: cfg.scope),
            URLQueryItem(name: "state", value: UUID().uuidString)
        ]
        if let pkce {
            items.append(URLQueryItem(name: "code_challenge", value: pkce.challenge))
            items.append(URLQueryItem(name: "code_challenge_method", value: "S256"))
        }
        items.append(contentsOf: cfg.extraAuthParams)
        comps?.queryItems = items

        guard let url = comps?.url else { throw ConnectorError.oauthFailed }

        let callback = try await present(url: url, callbackScheme: cfg.callbackScheme)
        guard
            let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value
        else { throw ConnectorError.oauthFailed }

        try await exchange(provider: provider, code: code, redirectURI: cfg.redirectURI, codeVerifier: pkce?.verifier)
    }

    func disconnect(_ provider: DataConnector) async {
        struct Req: Encodable { let action = "disconnect"; let provider: String }
        struct Resp: Decodable { let ok: Bool? }
        let _: Resp? = try? await supabase.functions.invoke(
            "connector-oauth",
            options: FunctionInvokeOptions(body: Req(provider: provider.rawValue))
        )
    }

    func todayValue(provider: DataConnector, metric: ConnectorMetric) async throws -> Double? {
        struct Req: Encodable { let action = "today"; let provider: String; let metric: String }
        struct Resp: Decodable { let value: Double?; let error: String? }
        let resp: Resp = try await supabase.functions.invoke(
            "connector-oauth",
            options: FunctionInvokeOptions(body: Req(provider: provider.rawValue, metric: metric.rawValue))
        )
        if let e = resp.error, e != "not_connected" { throw ConnectorError.server(e) }
        return resp.value
    }

    // MARK: - Token exchange (server-side)

    private func exchange(provider: DataConnector, code: String, redirectURI: String, codeVerifier: String?) async throws {
        struct Req: Encodable {
            let action = "exchange"
            let provider: String
            let code: String
            let redirectUri: String
            let codeVerifier: String?
        }
        struct Resp: Decodable { let ok: Bool?; let error: String? }
        let resp: Resp = try await supabase.functions.invoke(
            "connector-oauth",
            options: FunctionInvokeOptions(body: Req(
                provider: provider.rawValue, code: code, redirectUri: redirectURI, codeVerifier: codeVerifier
            ))
        )
        if let e = resp.error { throw ConnectorError.server(e) }
        guard resp.ok == true else { throw ConnectorError.oauthFailed }
    }

    // MARK: - Web auth session

    @MainActor
    private func present(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else if let err = error as? ASWebAuthenticationSessionError, err.code == .canceledLogin {
                    continuation.resume(throwing: ConnectorError.oauthCancelled)
                } else {
                    continuation.resume(throwing: error ?? ConnectorError.oauthFailed)
                }
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            webSession = session
            if !session.start() {
                continuation.resume(throwing: ConnectorError.oauthFailed)
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scene = UIApplication.shared.connectedScenes
            .first { $0.activationState == .foregroundActive } as? UIWindowScene
        if let key = scene?.keyWindow { return key }
        if let scene { return UIWindow(windowScene: scene) }
        return UIWindow(frame: .zero)
    }
}

// MARK: - PKCE

/// RFC 7636 PKCE pair for "public client" OAuth flows (no client secret on-device).
struct PKCE {
    let verifier: String
    let challenge: String

    static func generate() -> PKCE {
        let verifier = randomURLSafeString(length: 64)
        let digest = SHA256.hash(data: Data(verifier.utf8))
        let challenge = Data(digest).base64URLEncodedString()
        return PKCE(verifier: verifier, challenge: challenge)
    }

    private static func randomURLSafeString(length: Int) -> String {
        var bytes = [UInt8](repeating: 0, count: length)
        _ = SecRandomCopyBytes(kSecRandomDefault, length, &bytes)
        return Data(bytes).base64URLEncodedString()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

// MARK: - Provider configuration

struct OAuthConfig {
    /// Default callback used by Strava/Whoop/Notion -- the app's custom `reinspire://` scheme.
    static let defaultCallbackScheme = "reinspire"
    static let defaultRedirectURI = "reinspire://oauth-callback"

    let clientId: String
    let authorizeURL: String
    let scope: String
    var extraAuthParams: [URLQueryItem] = []
    /// Whether to generate and send a PKCE `code_challenge` (required for Google's
    /// installed-app flow, which has no client secret on-device).
    var usesPKCE: Bool = false
    /// URL scheme `ASWebAuthenticationSession` waits for the redirect on.
    var callbackScheme: String = OAuthConfig.defaultCallbackScheme
    /// Full redirect URI sent to the provider and to the edge function for token exchange.
    var redirectURI: String = OAuthConfig.defaultRedirectURI

    static func config(for provider: DataConnector) -> OAuthConfig {
        switch provider {
        case .strava:
            return OAuthConfig(
                clientId: OAuthSecrets.strava,
                authorizeURL: "https://www.strava.com/oauth/mobile/authorize",
                scope: "activity:read_all",
                extraAuthParams: [URLQueryItem(name: "approval_prompt", value: "auto")]
            )
        case .whoop:
            return OAuthConfig(
                clientId: OAuthSecrets.whoop,
                authorizeURL: "https://api.prod.whoop.com/oauth/oauth2/auth",
                scope: "read:workout read:cycles read:recovery offline"
            )
        case .notion:
            return OAuthConfig(
                clientId: OAuthSecrets.notion,
                authorizeURL: "https://api.notion.com/v1/oauth/authorize",
                scope: "",
                extraAuthParams: [
                    URLQueryItem(name: "owner", value: "user"),
                    URLQueryItem(name: "response_type", value: "code")
                ]
            )
        case .appleHealth, .appleFitness, .appleCalendar, .telegram, .appleClock:
            return OAuthConfig(clientId: "", authorizeURL: "", scope: "")
        }
    }
}

/// Client IDs are **public** and safe to ship. The matching client secrets live ONLY in the
/// Supabase Edge Function environment — never in the app. Fill these after registering each app.
enum OAuthSecrets {
    static let strava = "256944"
    static let whoop  = "<WHOOP_CLIENT_ID>"
    static let notion = "37cd872b-594c-813a-afff-003799004c78"

    /// Same OAuth client used for "Sign in with Google" (`GIDClientID` in Info.plist).
    /// Google's installed-app flow needs no client secret -- PKCE covers it.
    static let google = "403964246968-l9ibioo4q4hr42t83b44rt247hslbnsn.apps.googleusercontent.com"

    /// Reversed form of `google`'s client id, used as the redirect URL scheme.
    /// Already registered in Info.plist's `CFBundleURLTypes` for Google Sign-In.
    static let googleReversedClientId = "com.googleusercontent.apps.403964246968-l9ibioo4q4hr42t83b44rt247hslbnsn"
}
