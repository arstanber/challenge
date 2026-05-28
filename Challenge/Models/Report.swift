import Foundation

enum AIVerificationResult: String, Codable {
    case approved, rejected, pending, notApplicable

    var displayName: String {
        switch self {
        case .approved: return NSLocalizedString("Approved", comment: "")
        case .rejected: return NSLocalizedString("Rejected", comment: "")
        case .pending: return NSLocalizedString("Checking...", comment: "")
        case .notApplicable: return NSLocalizedString("Confirmed", comment: "")
        }
    }

    var icon: String {
        switch self {
        case .approved: return "checkmark.seal.fill"
        case .rejected: return "xmark.seal.fill"
        case .pending: return "clock.fill"
        case .notApplicable: return "checkmark.circle.fill"
        }
    }
}

struct Report: Codable, Identifiable {
    let id: UUID
    var activityId: UUID
    var photoURL: String?
    var comment: String?
    var aiResult: AIVerificationResult
    var aiExplanation: String?
    var progressValue: Double?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case activityId = "activity_id"
        case photoURL = "photo_url"
        case comment
        case aiResult = "ai_result"
        case aiExplanation = "ai_explanation"
        case progressValue = "progress_value"
        case createdAt = "created_at"
    }
}

struct CreateReportRequest: Codable {
    var activityId: UUID
    var photoURL: String?
    var comment: String?
    var progressValue: Double?

    enum CodingKeys: String, CodingKey {
        case activityId = "activity_id"
        case photoURL = "photo_url"
        case comment
        case progressValue = "progress_value"
    }
}
