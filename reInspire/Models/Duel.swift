import Foundation

/// A friend duel: both sides must close at least one task every day of the
/// window; more closed days wins. Mirrors the `duels` table plus the extras
/// `get_my_duels` returns (emails and per-side done-day arrays).
///
/// Calendar dates (`starts_on`, `ends_on`, done days) travel as "yyyy-MM-dd"
/// strings: the server buckets days in each participant's own timezone, so
/// the client treats them as opaque day labels and never re-buckets.
struct Duel: Codable, Identifiable, Hashable {
    enum CommitmentKind: String, Codable, CaseIterable { case none, days, socialForfeit = "social_forfeit" }
    enum Status: String, Codable {
        case pending, active, finished, cancelled
    }

    let id: UUID
    let challengerId: UUID
    let opponentId: UUID?
    let inviteCode: String
    let days: Int
    let status: Status
    let startsOn: String?
    let endsOn: String?
    let winnerId: UUID?
    let challengerEmail: String?
    let opponentEmail: String?
    let challengerDone: [String]
    let opponentDone: [String]
    /// Total tasks completed over the window per side -- the winner is whoever
    /// has more (default 0 for older payloads before the v2 scoring migration).
    let challengerTasks: Int
    let opponentTasks: Int
    let commitmentKind: CommitmentKind
    let stakeDays: Int?
    let forfeitText: String?

    enum CodingKeys: String, CodingKey {
        case id
        case challengerId = "challenger_id"
        case opponentId = "opponent_id"
        case inviteCode = "invite_code"
        case days
        case status
        case startsOn = "starts_on"
        case endsOn = "ends_on"
        case winnerId = "winner_id"
        case challengerEmail = "challenger_email"
        case opponentEmail = "opponent_email"
        case challengerDone = "challenger_done"
        case opponentDone = "opponent_done"
        case challengerTasks = "challenger_tasks"
        case opponentTasks = "opponent_tasks"
        case commitmentKind = "commitment_kind"
        case stakeDays = "stake_days"
        case forfeitText = "forfeit_text"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        challengerId = try c.decode(UUID.self, forKey: .challengerId)
        opponentId = try c.decodeIfPresent(UUID.self, forKey: .opponentId)
        inviteCode = try c.decode(String.self, forKey: .inviteCode)
        days = try c.decode(Int.self, forKey: .days)
        status = try c.decode(Status.self, forKey: .status)
        startsOn = try c.decodeIfPresent(String.self, forKey: .startsOn)
        endsOn = try c.decodeIfPresent(String.self, forKey: .endsOn)
        winnerId = try c.decodeIfPresent(UUID.self, forKey: .winnerId)
        challengerEmail = try c.decodeIfPresent(String.self, forKey: .challengerEmail)
        opponentEmail = try c.decodeIfPresent(String.self, forKey: .opponentEmail)
        challengerDone = try c.decodeIfPresent([String].self, forKey: .challengerDone) ?? []
        opponentDone = try c.decodeIfPresent([String].self, forKey: .opponentDone) ?? []
        challengerTasks = try c.decodeIfPresent(Int.self, forKey: .challengerTasks) ?? 0
        opponentTasks = try c.decodeIfPresent(Int.self, forKey: .opponentTasks) ?? 0
        commitmentKind = try c.decodeIfPresent(CommitmentKind.self, forKey: .commitmentKind) ?? .none
        stakeDays = try c.decodeIfPresent(Int.self, forKey: .stakeDays)
        forfeitText = try c.decodeIfPresent(String.self, forKey: .forfeitText)
    }

    // MARK: Day helpers

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        // Day labels are opaque server buckets -- parse/format in UTC so the
        // same label maps to the same day regardless of device timezone.
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    var startDate: Date? { startsOn.flatMap { Self.dayFormatter.date(from: $0) } }
    var endDate: Date? { endsOn.flatMap { Self.dayFormatter.date(from: $0) } }

    /// All day labels of the window, in order.
    var windowDays: [String] {
        guard let start = startDate else { return [] }
        var cal = Calendar.current
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        return (0..<days).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: start).map(Self.dayFormatter.string(from:))
        }
    }

    /// Days remaining including today; nil while pending.
    var daysLeft: Int? {
        guard let end = endDate else { return nil }
        let today = Calendar.current.startOfDay(for: Date())
        let diff = Calendar.current.dateComponents([.day], from: today, to: end).day ?? 0
        return max(0, diff + 1)
    }

    /// The window is over from this device's point of view -- worth asking
    /// the server to finalize (it re-checks both participants' timezones).
    var isOverdue: Bool {
        guard status == .active, let end = endDate else { return false }
        return Calendar.current.startOfDay(for: Date()) > end
    }

    // MARK: Sides

    func isChallenger(_ userId: UUID?) -> Bool { userId == challengerId }

    func myDone(_ userId: UUID?) -> [String] {
        isChallenger(userId) ? challengerDone : opponentDone
    }

    func theirDone(_ userId: UUID?) -> [String] {
        isChallenger(userId) ? opponentDone : challengerDone
    }

    /// Total tasks completed (the score that decides the duel).
    func myTasks(_ userId: UUID?) -> Int {
        isChallenger(userId) ? challengerTasks : opponentTasks
    }

    func theirTasks(_ userId: UUID?) -> Int {
        isChallenger(userId) ? opponentTasks : challengerTasks
    }

    /// Opponent display name from my point of view ("arslan" from
    /// "arslan@gmail.com"); placeholder while nobody joined yet.
    func opponentName(for userId: UUID?) -> String {
        let email = isChallenger(userId) ? opponentEmail : challengerEmail
        guard let email, let name = email.split(separator: "@").first else { return String(localized: "Соперник") }
        return String(name)
    }

    func didWin(_ userId: UUID?) -> Bool? {
        guard status == .finished else { return nil }
        guard let winnerId else { return nil }   // tie: both held the line
        return winnerId == userId
    }
}
