import Foundation
import Supabase

struct AIVerificationRequest: Encodable {
    let reportId: String
    let activityId: String
    let condition: String
    let photoURL: String
    let isExcuse: Bool
    let language: String

    enum CodingKeys: String, CodingKey {
        case reportId    = "report_id"
        case activityId  = "activity_id"
        case condition
        case photoURL    = "photo_url"
        case isExcuse    = "is_excuse"
        case language
    }
}

struct AIVerificationResponse: Decodable {
    let approved: Bool
    let excused: Bool
    let explanation: String
    /// Monthly verifications left, reported by the server-side rate limiter
    let remaining: Int?

    // excused defaults to false if missing (backward compat)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        approved    = try c.decode(Bool.self,   forKey: .approved)
        excused     = try c.decodeIfPresent(Bool.self, forKey: .excused) ?? false
        explanation = try c.decode(String.self, forKey: .explanation)
        remaining   = try c.decodeIfPresent(Int.self, forKey: .remaining)
    }

    enum CodingKeys: CodingKey { case approved, excused, explanation, remaining }
}

private struct SuggestConditionRequest: Encodable {
    let title: String
    let description: String
    let language: String
}

private struct SuggestConditionResponse: Decodable {
    let condition: String
}

final class AIVerificationService {
    static let shared = AIVerificationService()
    private init() {}

    /// Asks the AI what photo proves a task from its title/description.
    /// Returns nil if the server is unavailable or quota is exhausted.
    func suggestCondition(title: String, description: String = "") async -> String? {
        let body = SuggestConditionRequest(title: title, description: description, language: AppLanguage.current)
        do {
            let resp: SuggestConditionResponse = try await supabase.functions
                .invoke("suggest-condition", options: FunctionInvokeOptions(body: body))
            let trimmed = resp.condition.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        } catch {
            return nil
        }
    }

    /// Returns the user-entered proof requirement, or asks AI to create one.
    /// Falling back to the task title keeps photo verification enforceable even
    /// when the suggestion service is temporarily unavailable.
    func resolveCondition(
        title: String,
        description: String = "",
        existing: String? = nil
    ) async -> String {
        let entered = existing?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !entered.isEmpty { return entered }
        return await suggestCondition(title: title, description: description) ?? title
    }

    func verify(
        reportId: UUID,
        activityId: UUID,
        condition: String,
        photoURL: String,
        isExcuse: Bool = false
    ) async throws -> AIVerificationResponse {
        let body = AIVerificationRequest(
            reportId:   reportId.uuidString,
            activityId: activityId.uuidString,
            condition:  condition,
            photoURL:   photoURL,
            isExcuse:   isExcuse,
            language:   AppLanguage.current
        )
        return try await supabase.functions
            .invoke("verify-report", options: FunctionInvokeOptions(body: body))
    }
}
