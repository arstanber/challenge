import Foundation
import Supabase
import PostgREST
import Observation

@Observable
final class ProfileViewModel {
    var family: Family?
    var children: [FamilyMember] = []
    var isLoading = false
    var errorMessage: String?
    var totalCompleted: Int = 0
    var totalFailed: Int = 0

    private let authService = AuthService.shared

    var user: AppUser? { authService.currentUser }

    func loadProfile() async {
        guard let user = authService.currentUser else { return }
        isLoading = true
        do {
            let activities: [Activity] = try await supabase
                .from("activities")
                .select()
                .eq("user_id", value: user.id.uuidString)
                .execute()
                .value
            totalCompleted = activities.filter { $0.status == .completed }.count
            totalFailed = activities.filter { $0.status == .failed }.count

            if user.isParent, let familyId = user.familyId {
                let families: [Family] = try await supabase
                    .from("families")
                    .select()
                    .eq("id", value: familyId.uuidString)
                    .execute()
                    .value
                family = families.first

                children = try await supabase
                    .from("family_members")
                    .select()
                    .eq("family_id", value: familyId.uuidString)
                    .execute()
                    .value
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func createFamily() async {
        guard let user = authService.currentUser else { return }
        isLoading = true
        do {
            let code = String((0..<6).map { _ in "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789".randomElement()! })
            let familyInsert: [String: String] = ["parent_user_id": user.id.uuidString, "invite_code": code]
            let created: Family = try await supabase
                .from("families")
                .insert(familyInsert)
                .select()
                .single()
                .execute()
                .value
            family = created

            try await supabase
                .from("users")
                .update(["role": "parent", "family_id": created.id.uuidString])
                .eq("id", value: user.id.uuidString)
                .execute()
            authService.currentUser?.role = .parent
            authService.currentUser?.familyId = created.id
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func joinFamily(code: String) async {
        guard let user = authService.currentUser else { return }
        isLoading = true
        do {
            let families: [Family] = try await supabase
                .from("families")
                .select()
                .eq("invite_code", value: code.uppercased())
                .execute()
                .value
            guard let fam = families.first else {
                errorMessage = "Invalid invite code"
                isLoading = false
                return
            }
            let memberInsert: [String: String] = [
                "family_id": fam.id.uuidString,
                "child_user_id": user.id.uuidString
            ]
            try await supabase
                .from("family_members")
                .insert(memberInsert)
                .execute()

            try await supabase
                .from("users")
                .update(["role": "child", "family_id": fam.id.uuidString])
                .eq("id", value: user.id.uuidString)
                .execute()
            authService.currentUser?.role = .child
            authService.currentUser?.familyId = fam.id
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func signOut() {
        authService.signOut()
    }
}
