import Foundation

struct Workspace: Codable, Identifiable, Hashable {
    let id: UUID
    let userId: UUID
    var name: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case name
        case createdAt = "created_at"
    }
}
