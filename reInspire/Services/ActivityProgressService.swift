import Foundation
import Supabase

struct ActivityProgressSnapshot: Decodable {
    let activityId: UUID
    let dailyProgress: Double
    let targetReached: Bool

    enum CodingKeys: String, CodingKey {
        case activityId = "activity_id"
        case dailyProgress = "daily_progress"
        case targetReached = "target_reached"
    }
}

struct ActivityProgressUpdate: Decodable {
    let activityId: UUID
    let dailyProgress: Double
    let totalProgress: Double
    let displayProgress: Double
    let targetReached: Bool
    let reportCreated: Bool

    enum CodingKeys: String, CodingKey {
        case activityId = "activity_id"
        case dailyProgress = "daily_progress"
        case totalProgress = "total_progress"
        case displayProgress = "display_progress"
        case targetReached = "target_reached"
        case reportCreated = "report_created"
    }
}

enum ActivityProgressService {
    private struct RecordParams: Encodable {
        let activityId: UUID
        let value: Double

        enum CodingKeys: String, CodingKey {
            case activityId = "p_activity_id"
            case value = "p_value"
        }
    }

    static func loadToday() async throws -> [ActivityProgressSnapshot] {
        try await supabase
            .rpc("get_my_activity_progress_today")
            .execute()
            .value
    }

    static func record(activityId: UUID, value: Double) async throws -> ActivityProgressUpdate {
        try await supabase
            .rpc(
                "record_activity_progress",
                params: RecordParams(activityId: activityId, value: value)
            )
            .execute()
            .value
    }

    static func resetToday(activityId: UUID) async throws {
        try await supabase
            .rpc("reset_activity_progress_today", params: ["p_activity_id": activityId.uuidString])
            .execute()
    }
}
