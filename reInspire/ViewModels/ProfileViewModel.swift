import Foundation
import Supabase
import PostgREST
import Storage
import Observation

@Observable
@MainActor
final class ProfileViewModel {
    var family: Family?
    var children: [FamilyMember] = []
    /// All members of the caller's family (used by the child view to see who is
    /// in the family). Populated for any family member, parent or child.
    var familyMembers: [AppUser] = []
    var isLoading = false
    var errorMessage: String?
    var totalCompleted: Int = 0
    var totalFailed: Int = 0

    /// Set right after creating a child account so the UI can show the parent
    /// the login code + PIN to hand over (cleared when dismissed).
    var lastCreatedChild: CreatedChild?

    private let authService = AuthService.shared

    var user: AppUser? { authService.currentUser }

    /// Shareable invite text containing both the code and a deep link.
    var inviteShareText: String? {
        guard let code = family?.inviteCode else { return nil }
        return """
        Присоединяйся к моей семье в reInspire!
        Код: \(code)
        https://thechallenges.app/join?code=\(code)
        """
    }

    // Members grouped by family role for the mom/dad/children layout.
    var moms: [FamilyMember] { children.filter { $0.childUser?.familyRole == .mom } }
    var dads: [FamilyMember] { children.filter { $0.childUser?.familyRole == .dad } }
    var kids: [FamilyMember] { children.filter { ($0.childUser?.familyRole ?? .child) == .child } }

    /// child_user_ids of every kid in the family -- target list for the parent's
    /// "assign to all children" flow.
    var kidUserIds: [UUID] { kids.map(\.childUserId) }

    // Family members grouped by role for the child-side roster.
    var memberParents: [AppUser] { familyMembers.filter { ($0.familyRole ?? .child) != .child } }
    var memberKids: [AppUser] { familyMembers.filter { ($0.familyRole ?? .child) == .child } }

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
                    .select("id, family_id, child_user_id, joined_at, users:child_user_id(*)")
                    .eq("family_id", value: familyId.uuidString)
                    .execute()
                    .value
            }

            // Every family member (parent or child) can read the roster of who
            // is in the family (RLS: "Family members read each other").
            if let familyId = user.familyId {
                familyMembers = try await supabase
                    .from("users")
                    .select()
                    .eq("family_id", value: familyId.uuidString)
                    .execute()
                    .value
            } else {
                familyMembers = []
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

    /// A child leaves their family.
    func leaveFamily() async {
        guard let user = authService.currentUser else { return }
        isLoading = true
        do {
            try await supabase.rpc("leave_family").execute()
            authService.currentUser?.role = .individual
            authService.currentUser?.familyId = nil
            family = nil
            children = []
            familyMembers = []
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        _ = user
    }

    /// Whether the "code sent to parent" hint should show after a request.
    var leaveCodeRequested = false

    /// A child asks to leave: the server generates a code and pushes it to the
    /// parent (never to the child). The child then confirms with the code.
    @discardableResult
    func requestLeaveCode() async -> Bool {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await supabase.functions.invoke("family-leave-request")
            leaveCodeRequested = true
            return true
        } catch {
            errorMessage = "Не удалось отправить запрос. Попробуй ещё раз."
            return false
        }
    }

    /// A child confirms leaving with the code their parent received.
    @discardableResult
    func leaveFamilyWithCode(_ code: String) async -> Bool {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await supabase.rpc("leave_family_with_code", params: ["p_code": trimmed]).execute()
            authService.currentUser?.role = .individual
            authService.currentUser?.familyId = nil
            authService.currentUser?.familyRole = nil
            family = nil
            children = []
            familyMembers = []
            leaveCodeRequested = false
            return true
        } catch {
            errorMessage = "Неверный код. Попроси код у родителя."
            return false
        }
    }

    /// A parent removes one child from the family.
    func removeMember(_ member: FamilyMember) async {
        isLoading = true
        do {
            try await supabase.rpc("remove_family_member",
                                   params: ["p_child": member.childUserId.uuidString]).execute()
            children.removeAll { $0.id == member.id }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    /// A parent deletes the whole family.
    func deleteFamily() async {
        isLoading = true
        do {
            try await supabase.rpc("delete_family").execute()
            authService.currentUser?.role = .individual
            authService.currentUser?.familyId = nil
            family = nil
            children = []
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Child accounts

    struct CreatedChild: Decodable, Identifiable {
        let loginCode: String
        let userId: UUID
        var name: String = ""
        var pin: String = ""

        var id: UUID { userId }

        enum CodingKeys: String, CodingKey {
            case loginCode = "login_code"
            case userId = "user_id"
        }
    }

    /// Parent provisions a child account (name + PIN) via the edge function.
    @discardableResult
    func createChild(name: String, pin: String) async -> Bool {
        struct Req: Encodable { let name: String; let pin: String }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            var created: CreatedChild = try await supabase.functions
                .invoke("create-child", options: FunctionInvokeOptions(
                    body: Req(name: name.trimmingCharacters(in: .whitespaces), pin: pin)
                ))
            created.name = name.trimmingCharacters(in: .whitespaces)
            created.pin = pin
            lastCreatedChild = created
            AnalyticsService.shared.track(.activityCreated, ["type": "child_account"])
            await loadProfile()
            return true
        } catch {
            errorMessage = "Не удалось создать аккаунт ребёнка"
            return false
        }
    }

    // MARK: - Family roles

    /// Assign a member to the mom / dad / child bucket (parent-only RPC).
    func setFamilyRole(_ member: FamilyMember, to role: FamilyRole) async {
        do {
            try await supabase.rpc("set_family_role", params: [
                "p_member": member.childUserId.uuidString,
                "p_role": role.rawValue,
            ]).execute()
            await loadProfile()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The parent picks their own mom / dad label.
    func setMyFamilyRole(_ role: FamilyRole) async {
        guard let uid = authService.currentUser?.id else { return }
        do {
            try await supabase.rpc("set_family_role", params: [
                "p_member": uid.uuidString,
                "p_role": role.rawValue,
            ]).execute()
            authService.currentUser?.familyRole = role
            await loadProfile()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Profile editing (display name + avatar)

    /// Update the signed-in user's display name. Empty clears it (falls back to
    /// the email local part via `displayLabel`).
    func updateDisplayName(_ name: String) async {
        guard let id = authService.currentUser?.id else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        isLoading = true
        defer { isLoading = false }
        do {
            try await supabase
                .from("users")
                .update(["display_name": trimmed.isEmpty ? nil : trimmed])
                .eq("id", value: id.uuidString)
                .execute()
            authService.currentUser?.displayName = trimmed.isEmpty ? nil : trimmed
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Upload a new avatar (JPEG data) to the avatars bucket and store its public
    /// URL on the users row. Returns true on success.
    @discardableResult
    func uploadAvatar(_ jpeg: Data) async -> Bool {
        guard let id = authService.currentUser?.id else { return false }
        isLoading = true
        defer { isLoading = false }
        do {
            let path = "\(id.uuidString)/\(UUID().uuidString).jpg"
            try await supabase.storage
                .from(Constants.Storage.avatarsBucket)
                .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg"))
            let url = try supabase.storage
                .from(Constants.Storage.avatarsBucket)
                .getPublicURL(path: path)
                .absoluteString
            try await supabase
                .from("users")
                .update(["avatar_url": url])
                .eq("id", value: id.uuidString)
                .execute()
            authService.currentUser?.avatarURL = url
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Pending invite (deep link / shake while signed out or before join)

    /// If a family code was captured from a deep link or shake, join now.
    func consumePendingInvite() async {
        guard let code = authService.pendingFamilyCode, !code.isEmpty else { return }
        // Already in a family -- nothing to do, just clear it.
        guard authService.currentUser?.familyId == nil else {
            authService.pendingFamilyCode = nil
            return
        }
        await joinFamily(code: code)
        authService.pendingFamilyCode = nil
    }

    func signOut() {
        authService.signOut()
    }
}
