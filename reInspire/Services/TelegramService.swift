import Foundation
import Supabase
import Observation

/// Status of the current user's Telegram link, returned by the
/// `telegram_link_status` SECURITY DEFINER RPC (telegram_links itself has no
/// client-facing RLS policies — same pattern as connector_tokens).
private struct TelegramLinkStatus: Decodable {
    var username: String?
    var linkedAt: Date?

    enum CodingKeys: String, CodingKey {
        case username
        case linkedAt = "linked_at"
    }
}

/// Lets the user link their Telegram account to the reInspire bot so they can
/// create tasks, submit photo proof, and get notifications from Telegram.
///
/// Linking flow:
///  1. App generates a short random code and stores it in `telegram_link_codes`
///     (RLS lets a user write only their own codes).
///  2. App opens `t.me/<bot>?start=<code>` — Telegram pre-fills "/start <code>".
///  3. The bot's `telegram-webhook` function verifies the code and upserts a row
///     in `telegram_links` (service_role only).
///  4. The app polls `telegram_link_status()` until it sees a linked username.
@MainActor
@Observable
final class TelegramService {
    static let shared = TelegramService()
    private init() {}

    var isLinked = false
    var linkedUsername: String?
    var pendingCode: String?
    var isLoading = false
    var errorMessage: String?

    private static let codeLength = 8
    private static let codeLifetime: TimeInterval = 10 * 60

    /// Deep link that opens Telegram with `/start <code>` pre-filled.
    func deepLink(for code: String) -> URL? {
        URL(string: "https://t.me/\(Constants.Telegram.botUsername)?start=\(code)")
    }

    func refreshStatus() async {
        guard let userId = AuthService.shared.currentUser?.id else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let rows: [TelegramLinkStatus] = try await supabase
                .rpc("telegram_link_status")
                .execute()
                .value
            if let status = rows.first {
                isLinked = true
                linkedUsername = status.username
                pendingCode = nil
            } else {
                isLinked = false
                linkedUsername = nil
            }
            _ = userId
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Generates a fresh linking code and returns the deep link to open in Telegram.
    func generateLinkCode() async -> URL? {
        guard let userId = AuthService.shared.currentUser?.id else { return nil }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let code = Self.randomCode()
            try await supabase
                .from("telegram_link_codes")
                .insert([
                    "code": code,
                    "user_id": userId.uuidString,
                    "expires_at": ISO8601DateFormatter().string(from: Date().addingTimeInterval(Self.codeLifetime)),
                ])
                .execute()
            pendingCode = code
            return deepLink(for: code)
        } catch {
            errorMessage = error.localizedDescription
            return nil
        }
    }

    func unlink() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await supabase.rpc("telegram_unlink").execute()
            isLinked = false
            linkedUsername = nil
            pendingCode = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func randomCode() -> String {
        let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789") // no ambiguous chars
        return String((0..<codeLength).map { _ in alphabet.randomElement()! })
    }
}
