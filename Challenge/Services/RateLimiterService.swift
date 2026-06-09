import Foundation
import Supabase
import os.log

private let logger = Logger(subsystem: "com.challenge", category: "RateLimiterService")

enum AIFeature: String {
    case verifyReport = "verify-report"
    case parseTasks   = "parse-tasks"
    case morningBrief = "morning-brief"
    case planGoal     = "plan-goal"

    var usageKey: String {
        switch self {
        case .verifyReport: return "verify-report"
        case .parseTasks:   return "parse-tasks-group"
        case .morningBrief: return "coach-group"
        case .planGoal:     return "plan-goal"
        }
    }

    func limit(for plan: UserPlan) -> Int {
        switch self {
        case .verifyReport:
            switch plan { case .free: return 5;  case .premium: return 15; case .family: return 20; case .max: return 30 }
        case .parseTasks:
            switch plan { case .free: return 1;  case .premium: return 5;  case .family: return 8;  case .max: return 10 }
        case .morningBrief:
            switch plan { case .free: return 1;  case .premium: return 5;  case .family: return 8;  case .max: return 12 }
        case .planGoal:
            switch plan { case .free: return 3;  case .premium: return 10; case .family: return 10; case .max: return 20 }
        }
    }
}

@Observable
final class RateLimiterService {
    static let shared = RateLimiterService()

    private(set) var usage: [String: Int] = [:]

    private var currentMonth: String {
        let f = DateFormatter(); f.dateFormat = "yyyy-MM"; return f.string(from: .now)
    }

    private init() {}

    func fetchUsage() async {
        guard let userId = AuthService.shared.currentUser?.id else { return }
        do {
            struct Row: Decodable { let feature: String; let count: Int }
            let rows: [Row] = try await supabase
                .from("ai_usage")
                .select("feature, count")
                .eq("user_id", value: userId.uuidString)
                .eq("month", value: currentMonth)
                .execute()
                .value
            await MainActor.run {
                usage = Dictionary(uniqueKeysWithValues: rows.map { ($0.feature, $0.count) })
            }
        } catch {
            logger.error("RateLimiter fetchUsage: \(error)")
        }
    }

    func canUse(_ feature: AIFeature) -> Bool {
        guard let plan = AuthService.shared.currentUser?.plan else { return false }
        return (usage[feature.usageKey] ?? 0) < feature.limit(for: plan)
    }

    func remaining(_ feature: AIFeature) -> Int {
        guard let plan = AuthService.shared.currentUser?.plan else { return 0 }
        return max(0, feature.limit(for: plan) - (usage[feature.usageKey] ?? 0))
    }

    // Called after the Edge Function responds with `remaining` in the payload,
    // so the local cache stays in sync without an extra network round-trip.
    @MainActor
    func syncRemaining(_ remaining: Int, for feature: AIFeature) {
        guard let plan = AuthService.shared.currentUser?.plan else { return }
        usage[feature.usageKey] = feature.limit(for: plan) - remaining
    }
}
