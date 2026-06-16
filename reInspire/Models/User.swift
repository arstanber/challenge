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

/// Display/grouping bucket inside a family. Mom and dad both map to the
/// `parent` permission role; child maps to `child` (see set_family_role RPC).
enum FamilyRole: String, Codable, CaseIterable, Identifiable {
    case mom, dad, child

    var id: String { rawValue }

    var title: String {
        switch self {
        case .mom: return "Мама"
        case .dad: return "Папа"
        case .child: return "Ребёнок"
        }
    }

    var icon: String {
        switch self {
        case .mom: return "figure.dress"
        case .dad: return "figure"
        case .child: return "figure.child"
        }
    }
}

struct AppUser: Codable, Identifiable {
    let id: UUID
    var email: String
    var avatarURL: String?
    var plan: UserPlan
    var role: UserRole
    var familyId: UUID?
    var createdAt: Date
    /// Friendly name (set for parent-provisioned child accounts; may be nil for
    /// self-registered users who only have an email).
    var displayName: String?
    /// mom / dad / child grouping inside the family.
    var familyRole: FamilyRole?
    /// True for accounts a parent created with a name + PIN.
    var isChildAccount: Bool?
    /// Short code a child account signs in with (only readable by the parent).
    var childLoginCode: String?
    /// True once a child account has replaced its synthetic email/PIN with a
    /// real email + password. Forced on first sign-in for child accounts.
    var childCredentialsSet: Bool?
    // Referral program (20260612c_referrals.sql)
    var referralCode: String?
    var referredBy: UUID?
    /// Temporary PRO from the welcome trial (7 days on signup) and referral
    /// rewards; premium while in the future.
    var proUntil: Date?
    /// Streak freezes claimed from referrals, added to the freeze wallet.
    var bonusFreezes: Int?

    enum CodingKeys: String, CodingKey {
        case id, email
        case avatarURL = "avatar_url"
        case plan, role
        case familyId = "family_id"
        case createdAt = "created_at"
        case referralCode = "referral_code"
        case referredBy = "referred_by"
        case proUntil = "pro_until"
        case bonusFreezes = "bonus_freezes"
        case displayName = "display_name"
        case familyRole = "family_role"
        case isChildAccount = "is_child_account"
        case childLoginCode = "child_login_code"
        case childCredentialsSet = "child_credentials_set"
    }

    var isParent: Bool { role == .parent }

    /// A child account that has not yet set a real email + password. The app
    /// blocks them on a registration screen until they do.
    var needsChildCredentials: Bool {
        (isChildAccount ?? false) && !(childCredentialsSet ?? false)
    }

    /// Best human-readable label: explicit name, else the local part of the email.
    var displayLabel: String {
        if let displayName, !displayName.isEmpty { return displayName }
        return email.split(separator: "@").first.map(String.init) ?? email
    }

    /// True while referral-granted PRO time is still running.
    var hasReferralPro: Bool {
        guard let proUntil else { return false }
        return proUntil > Date()
    }

    var isPremium: Bool { plan != .free || hasReferralPro }
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
