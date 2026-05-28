import Foundation

enum UserPlan: String, Codable {
    case free, premium
}

enum UserRole: String, Codable {
    case parent, child, individual
}

struct AppUser: Codable, Identifiable {
    let id: UUID
    var email: String
    var avatarURL: String?
    var plan: UserPlan
    var role: UserRole
    var familyId: UUID?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, email
        case avatarURL = "avatar_url"
        case plan, role
        case familyId = "family_id"
        case createdAt = "created_at"
    }

    var isParent: Bool { role == .parent }
    var isPremium: Bool { plan == .premium }
}

struct AuthSession: Codable {
    let accessToken: String
    let refreshToken: String
    let user: AuthUser

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case user
    }
}

struct AuthUser: Codable {
    let id: UUID
    let email: String?
}
