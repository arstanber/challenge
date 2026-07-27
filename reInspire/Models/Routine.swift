import Foundation

enum RoutinePeriod: String, Codable, CaseIterable, Identifiable {
    case morning
    case evening
    case anytime

    var id: String { rawValue }

    var title: String {
        switch self {
        case .morning: return String(localized: "Утро")
        case .evening: return String(localized: "Вечер")
        case .anytime: return String(localized: "В любое время")
        }
    }

    var defaultIcon: String {
        switch self {
        case .morning: return "sun.max.fill"
        case .evening: return "moon.stars.fill"
        case .anytime: return "sparkles"
        }
    }
}

struct Routine: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    var name: String
    var icon: String
    var period: RoutinePeriod
    var activityIds: [UUID]
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name, icon, period
        case activityIds = "activity_ids"
        case createdAt = "created_at"
    }
}
