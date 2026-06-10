import Foundation
import UIKit
import AuthenticationServices
import Supabase

/// OAuth2 web-API connectors (Strava, Google Fit, Garmin, Whoop, Fitbit).
///
/// Flow:
/// 1. `ASWebAuthenticationSession` opens the provider's consent page.
/// 2. Provider redirects to `challenge://oauth-callback?code=…`.
/// 3. We hand the `code` to the `connector-oauth` Edge Function, which exchanges it for
///    tokens **using the client secret server-side** and stores them in `connector_tokens`.
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

        var comps = URLComponents(string: cfg.authorizeURL)
        var items = [
            URLQueryItem(name: "client_id", value: cfg.clientId),
            URLQueryItem(name: "redirect_uri", value: OAuthConfig.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: cfg.scope),
            URLQueryItem(name: "state", value: UUID().uuidString)
        ]
        items.append(contentsOf: cfg.extraAuthParams)
        comps?.queryItems = items

        guard let url = comps?.url else { throw ConnectorError.oauthFailed }

        let callback = try await present(url: url)
        guard
            let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                .queryItems?.first(where: { $0.name == "code" })?.value
        else { throw ConnectorError.oauthFailed }

        try await exchange(provider: provider, code: code)
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

    private func exchange(provider: DataConnector, code: String) async throws {
        struct Req: Encodable { let action = "exchange"; let provider: String; let code: String; let redirectUri: String }
        struct Resp: Decodable { let ok: Bool?; let error: String? }
        let resp: Resp = try await supabase.functions.invoke(
            "connector-oauth",
            options: FunctionInvokeOptions(body: Req(
                provider: provider.rawValue, code: code, redirectUri: OAuthConfig.redirectURI
            ))
        )
        if let e = resp.error { throw ConnectorError.server(e) }
        guard resp.ok == true else { throw ConnectorError.oauthFailed }
    }

    // MARK: - Web auth session

    @MainActor
    private func present(url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: OAuthConfig.callbackScheme
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

// MARK: - Provider configuration

struct OAuthConfig {
    static let callbackScheme = "challenge"
    static let redirectURI = "challenge://oauth-callback"

    let clientId: String
    let authorizeURL: String
    let scope: String
    var extraAuthParams: [URLQueryItem] = []

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
        case .appleHealth, .appleFitness:
            return OAuthConfig(clientId: "", authorizeURL: "", scope: "")
        }
    }
}

/// Client IDs are **public** and safe to ship. The matching client secrets live ONLY in the
/// Supabase Edge Function environment — never in the app. Fill these after registering each app.
enum OAuthSecrets {
    static let strava = "<STRAVA_CLIENT_ID>"
    static let whoop  = "<WHOOP_CLIENT_ID>"
}
