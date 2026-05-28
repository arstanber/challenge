import Foundation
import Supabase
import PostgREST
import Observation

@Observable
final class ActivitiesViewModel {
    var myActivities: [Activity] = []
    var parentActivities: [Activity] = []
    var isLoading = false
    var errorMessage: String?

    private let authService = AuthService.shared

    var activeCount: Int { myActivities.filter { $0.status == .active }.count }
    var canCreateMore: Bool {
        guard let user = authService.currentUser else { return false }
        return user.isPremium || activeCount < Constants.App.maxFreeActivities
    }

    func loadActivities() async {
        guard let user = authService.currentUser else { return }
        isLoading = true
        errorMessage = nil
        do {
            let all: [Activity] = try await supabase
                .from("activities")
                .select()
                .eq("user_id", value: user.id.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
            myActivities = all.filter { $0.assignedBy == nil }
            parentActivities = all.filter { $0.assignedBy != nil }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func deleteActivity(_ activity: Activity) async {
        do {
            try await supabase
                .from("activities")
                .delete()
                .eq("id", value: activity.id.uuidString)
                .execute()
            myActivities.removeAll { $0.id == activity.id }
            parentActivities.removeAll { $0.id == activity.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markCompleted(_ activity: Activity) async {
        do {
            try await supabase
                .from("activities")
                .update(["status": "completed"])
                .eq("id", value: activity.id.uuidString)
                .execute()
            if let idx = myActivities.firstIndex(where: { $0.id == activity.id }) {
                myActivities[idx].status = .completed
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
