import Foundation
import Supabase

struct AIVerificationRequest: Encodable {
    let reportId: String
    let activityId: String
    let condition: String
    let photoURL: String
    let isExcuse: Bool

    enum CodingKeys: String, CodingKey {
        case reportId    = "report_id"
        case activityId  = "activity_id"
        case condition
        case photoURL    = "photo_url"
        case isExcuse    = "is_excuse"
    }
}

struct AIVerificationResponse: Decodable {
    let approved: Bool
    let excused: Bool
    let explanation: String

    // excused defaults to false if missing (backward compat)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        approved    = try c.decode(Bool.self,   forKey: .approved)
        excused     = try c.decodeIfPresent(Bool.self, forKey: .excused) ?? false
        explanation = try c.decode(String.self, forKey: .explanation)
    }

    enum CodingKeys: CodingKey { case approved, excused, explanation }
}

final class AIVerificationService {
    static let shared = AIVerificationService()
    private init() {}

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
            isExcuse:   isExcuse
        )
        return try await supabase.functions
            .invoke("verify-report", options: FunctionInvokeOptions(body: body))
    }
}
