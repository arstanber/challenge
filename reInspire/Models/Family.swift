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

// MARK: - Assignment overview (parent view of who completed an assigned task)

/// Where one child stands on an assigned task.
enum AssignmentChildState {
    case done       // approved / completed / excuse accepted
    case pending    // photo submitted, AI still checking
    case rejected   // last photo was not approved
    case waiting    // nothing submitted yet

    var title: String {
        switch self {
        case .done:     return "Выполнил"
        case .pending:  return "На проверке"
        case .rejected: return "Не принято"
        case .waiting:  return "Ждём"
        }
    }

    var icon: String {
        switch self {
        case .done:     return "checkmark.circle.fill"
        case .pending:  return "clock.fill"
        case .rejected: return "xmark.circle.fill"
        case .waiting:  return "hourglass"
        }
    }
}

/// One child's status within a grouped assignment.
struct AssignmentChildStatus: Identifiable {
    let id: UUID            // child user id
    let name: String
    let avatarURL: String?
    let state: AssignmentChildState
    let lastReportAt: Date?
}

/// A task a parent assigned to one or more children, with per-child completion.
struct AssignmentOverview: Identifiable {
    let id: String          // assignment_group_id, or activity id for legacy rows
    let title: String
    let description: String
    let deadline: Date?
    let children: [AssignmentChildStatus]

    var doneCount: Int { children.filter { $0.state == .done }.count }
    var total: Int { children.count }
}
