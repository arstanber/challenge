import Foundation
import Supabase

// MARK: - AI Coach Service (#10 #11 #12)
// All AI calls route through Supabase Edge Functions.
// Deploy the functions from supabase/functions/ alongside this file.

// MARK: #10 — Morning Brief

struct MorningBrief: Decodable {
    let greeting: String        // "You're on a 7-day streak — keep it up!"
    let topTasks: [String]      // up to 3 activity titles to focus on today
    let motivationTip: String   // one-liner tip
    let error: String?
}

// MARK: #11 — Failure Analysis

struct FailureAnalysis: Decodable {
    let reason: String          // AI guess why it was hard
    let suggestion: String      // actionable next step
    let reschedule: Bool        // should the user try again tomorrow?
    let error: String?
}

// MARK: #12 — Goal Split

struct GoalSplit: Decodable {
    let subtasks: [SplitTask]
    let error: String?
}

struct SplitTask: Decodable, Identifiable {
    var id: UUID { UUID() }     // synthetic — not from server
    let title: String
    let estimatedDays: Int?
}

// MARK: - Service

final class AICoachService {
    static let shared = AICoachService()
    private init() {}

    // MARK: #10 Morning Brief

    private struct BriefRequest: Encodable {
        let userId: String
        let streakCurrent: Int
        let todayTasks: [String]    // titles of active activities
    }

    func morningBrief(streakCurrent: Int, todayTasks: [String]) async throws -> MorningBrief {
        guard let userId = AuthService.shared.currentUser?.id else {
            throw CoachError.notAuthenticated
        }
        let req = BriefRequest(userId: userId.uuidString,
                               streakCurrent: streakCurrent,
                               todayTasks: todayTasks)
        let response: MorningBrief = try await supabase.functions
            .invoke("morning-brief", options: FunctionInvokeOptions(body: req))
        if let e = response.error { throw CoachError.server(e) }
        return response
    }

    // MARK: #11 Failure Analysis

    private struct FailureRequest: Encodable {
        let activityTitle: String
        let activityType: String
        let streakBefore: Int
        let userReason: String?     // optional text from user
    }

    func analyzeFailure(activity: Challenge.Activity, userReason: String? = nil) async throws -> FailureAnalysis {
        let req = FailureRequest(activityTitle: activity.title,
                                 activityType: activity.type.rawValue,
                                 streakBefore: activity.streakCurrent,
                                 userReason: userReason)
        let response: FailureAnalysis = try await supabase.functions
            .invoke("analyze-failure", options: FunctionInvokeOptions(body: req))
        if let e = response.error { throw CoachError.server(e) }
        return response
    }

    // MARK: #12 Goal Split

    private struct SplitRequest: Encodable {
        let goalTitle: String
        let goalDescription: String
        let targetValue: Double?
        let deadlineDays: Int?
    }

    func splitGoal(activity: Challenge.Activity) async throws -> GoalSplit {
        let deadline = activity.deadline.map {
            Calendar.current.dateComponents([.day], from: Date(), to: $0).day ?? 30
        }
        let req = SplitRequest(goalTitle: activity.title,
                               goalDescription: activity.description,
                               targetValue: activity.goalTarget,
                               deadlineDays: deadline)
        let response: GoalSplit = try await supabase.functions
            .invoke("split-goal", options: FunctionInvokeOptions(body: req))
        if let e = response.error { throw CoachError.server(e) }
        return response
    }
}

enum CoachError: LocalizedError {
    case notAuthenticated
    case server(String)

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not signed in"
        case .server(let msg):  return msg
        }
    }
}
