import Foundation
import Supabase
import os.log

/// GDPR data-rights helpers: export everything we hold on the user (right to
/// access / portability) and permanently erase the account (right to erasure).
@MainActor
final class PrivacyService {
    static let shared = PrivacyService()
    private init() {}

    private let logger = Logger(subsystem: "com.reinspire", category: "PrivacyService")

    /// Tables the user owns. Each row set is embedded verbatim into the export
    /// so the file is a faithful copy of the personal data we store. The owner
    /// column differs: the profile table keys on `id`, the rest on `user_id`.
    /// Connector tokens are deliberately excluded -- they are secrets, not
    /// user-facing personal data.
    private let exportTables: [(table: String, ownerColumn: String)] = [
        ("users", "id"),
        ("activities", "user_id"),
        ("streak_freezes", "user_id"),
    ]

    /// Builds a JSON document of the user's data and writes it to a temp file,
    /// returning its URL for a share sheet. Throws on a hard failure; a table
    /// the user simply has no rows in is represented as an empty array.
    func exportData() async throws -> URL {
        guard let uid = AuthService.shared.currentUser?.id.uuidString.lowercased() else {
            throw NSError(domain: "PrivacyService", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Not signed in"])
        }

        var payload: [String: Any] = [
            "exported_at": ISO8601DateFormatter().string(from: Date()),
            "app": "reInspire",
        ]

        for entry in exportTables {
            let data = try await supabase
                .from(entry.table)
                .select()
                .eq(entry.ownerColumn, value: uid)
                .execute()
                .data
            let rows = (try? JSONSerialization.jsonObject(with: data)) ?? []
            payload[entry.table] = rows
        }

        // Reports have no user_id column -- they're owned via activity_id.
        struct IdRow: Decodable { let id: UUID }
        let activityIds: [IdRow] = try await supabase
            .from("activities").select("id").eq("user_id", value: uid).execute().value
        if activityIds.isEmpty {
            payload["reports"] = []
        } else {
            let data = try await supabase
                .from("reports").select()
                .in("activity_id", values: activityIds.map { $0.id.uuidString })
                .execute()
                .data
            payload["reports"] = (try? JSONSerialization.jsonObject(with: data)) ?? []
        }

        let json = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("reInspire-данные.json")
        try json.write(to: url, options: .atomic)
        return url
    }

    /// Permanently erases the account via the `delete-account` edge function,
    /// then signs the user out locally. Returns true on success.
    @discardableResult
    func deleteAccount() async -> Bool {
        struct Ack: Decodable { let ok: Bool? }
        do {
            let ack: Ack = try await supabase.functions.invoke("delete-account")
            guard ack.ok == true else {
                logger.error("delete-account returned not-ok")
                return false
            }
            AnalyticsService.shared.track(.accountDeleted)
            AuthService.shared.signOut()
            return true
        } catch {
            logger.error("delete-account failed: \(error.localizedDescription)")
            return false
        }
    }
}
