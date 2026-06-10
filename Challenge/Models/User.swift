import Foundation

enum UserPlan: String, Codable, Comparable {
    case free, premium, family, max

    /// Tier ordering used to pick the highest active entitlement.
    var rank: Int {
        switch self {
        case .free: return 0
        case .premium: return 1
        case .family: return 2
        case .max: return 3
        }
    }

    static func < (lhs: UserPlan, rhs: UserPlan) -> Bool { lhs.rank < rhs.rank }

    var displayName: String {
        switch self {
        case .free: return "Free"
        case .premium: return "Premium"
        case .family: return "Family"
        case .max: return "Max"
        }
    }

    /// Max-tier connectors: Strava, Whoop, Notion, Google Docs, Google Drive, Gmail.
    var hasMaxConnectors: Bool { self == .max }
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
    var isPremium: Bool { plan != .free }
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
