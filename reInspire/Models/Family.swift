import Foundation

struct Family: Codable, Identifiable {
    let id: UUID
    var parentUserId: UUID
    var inviteCode: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case parentUserId = "parent_user_id"
        case inviteCode = "invite_code"
        case createdAt = "created_at"
    }
}

struct FamilyMember: Codable, Identifiable {
    let id: UUID
    var familyId: UUID
    var childUserId: UUID
    var joinedAt: Date
    var childUser: AppUser?

    enum CodingKeys: String, CodingKey {
        case id
        case familyId = "family_id"
        case childUserId = "child_user_id"
        case joinedAt = "joined_at"
        case childUser = "users"
    }
}

struct ChildProgress: Identifiable {
    let id: UUID
    var member: FamilyMember
    var activities: [Activity]
    var recentReports: [Report]
}
