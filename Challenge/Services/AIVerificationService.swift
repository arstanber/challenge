import Foundation
import Supabase

struct AIVerificationRequest: Encodable {
    let reportId: String
    let activityId: String
    let condition: String
    let photoURL: String

    enum CodingKeys: String, CodingKey {
        case reportId = "report_id"
        case activityId = "activity_id"
        case condition
        case photoURL = "photo_url"
    }
}

struct AIVerificationResponse: Decodable {
    let approved: Bool
    let explanation: String
}

final class AIVerificationService {
    static let shared = AIVerificationService()
    private init() {}

    func verify(reportId: UUID, activityId: UUID, condition: String, photoURL: String) async throws -> AIVerificationResponse {
        let body = AIVerificationRequest(
            reportId: reportId.uuidString,
            activityId: activityId.uuidString,
            condition: condition,
            photoURL: photoURL
        )
        return try await supabase.functions
            .invoke("verify-report", options: FunctionInvokeOptions(body: body))
    }
}
