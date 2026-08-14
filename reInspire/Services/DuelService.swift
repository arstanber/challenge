import Foundation
import Supabase
import PostgREST
import Observation
import os.log

private let logger = Logger(subsystem: "com.reinspire", category: "DuelService")

/// Friend duels client. All mutations go through SECURITY DEFINER RPCs
/// (create_duel / join_duel / cancel_duel / finish_duel_if_due); the list
/// comes from get_my_duels in one round trip.
@MainActor
@Observable
final class DuelService {
    static let shared = DuelService()

    private(set) var duels: [Duel] = []
    private(set) var isLoading = false
    private(set) var commitmentDays = 1
    var errorMessage: String?

    private init() {}

    private var myUserId: UUID? { AuthService.shared.currentUser?.id }

    // MARK: - Load

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            commitmentDays = try await supabase.rpc("my_commitment_days").execute().value
            duels = try await supabase.rpc("get_my_duels").execute().value
            if await finalizeOverdue() {
                duels = try await supabase.rpc("get_my_duels").execute().value
            }
        } catch {
            logger.error("get_my_duels failed: \(error)")
            errorMessage = AppLanguage.current == "ru" ? "Не удалось загрузить дуэли" : "Couldn't load duels"
        }
    }

    /// Ask the server to finalize overdue duels. Returns true when at least
    /// one transitioned, so the caller re-fetches. The participant who
    /// triggers the transition also notifies the other side.
    private func finalizeOverdue() async -> Bool {
        struct FinishedRow: Decodable {
            let status: Duel.Status
            let winnerId: UUID?
            enum CodingKeys: String, CodingKey {
                case status
                case winnerId = "winner_id"
            }
        }
        var finalizedAny = false
        for duel in duels where duel.isOverdue {
            do {
                let row: FinishedRow = try await supabase
                    .rpc("settle_duel_commitment", params: ["p_duel_id": duel.id.uuidString])
                    .execute()
                    .value
                guard row.status == .finished else { continue }
                finalizedAny = true
                AnalyticsService.shared.track(.duelFinished)
                if row.winnerId == myUserId {
                    ReviewRequestManager.shared.registerDuelVictory()
                }
                await notifyOpponentAboutFinish(duel: duel, winnerId: row.winnerId)
            } catch {
                logger.error("finish_duel_if_due failed for \(duel.id): \(error)")
            }
        }
        return finalizedAny
    }

    private func notifyOpponentAboutFinish(duel: Duel, winnerId: UUID?) async {
        guard let me = myUserId else { return }
        let otherId = duel.isChallenger(me) ? duel.opponentId : duel.challengerId
        guard let otherId else { return }
        let lang = await recipientLanguage(otherId)
        let title: String
        let body: String
        if lang == "ru" {
            title = "Дуэль завершена ⚔️"
            if winnerId == nil {
                body = "Ничья: оба продержались до конца. Реванш?"
            } else if winnerId == otherId {
                body = "Ты победил! Соперник не удержал темп."
            } else {
                body = "Победил соперник. Реванш расставит всё по местам."
            }
        } else {
            title = "Duel finished ⚔️"
            if winnerId == nil {
                body = "Draw: you both held on to the end. Rematch?"
            } else if winnerId == otherId {
                body = "You won! Your opponent couldn't keep the pace."
            } else {
                body = "Your opponent won. A rematch will settle it."
            }
        }
        await NotificationService.shared.sendPush(toUserId: otherId, title: title, body: body)
    }

    /// Looks up another user's language for a cross-user push (recipient's
    /// language, not the sender's device locale) -- `users` RLS only allows
    /// reading family members, so this goes through a narrow RPC. Defaults to
    /// "ru" on error, matching the server-side default for the column.
    private func recipientLanguage(_ userId: UUID) async -> String {
        do {
            return try await supabase
                .rpc("get_user_language", params: ["p_user_id": userId.uuidString])
                .execute()
                .value
        } catch {
            logger.error("get_user_language failed: \(error)")
            return "ru"
        }
    }

    // MARK: - Mutations

    /// Creates a duel and returns its invite code for sharing.
    func createDuel(days: Int = 7, commitment: Duel.CommitmentKind = .none,
                    stakeDays: Int? = nil, forfeitText: String? = nil) async -> String? {
        struct Parameters: Encodable {
            let days: Int
            let kind: String
            let stakeDays: Int?
            let forfeitText: String?
            enum CodingKeys: String, CodingKey {
                case days = "p_days"
                case kind = "p_kind"
                case stakeDays = "p_stake_days"
                case forfeitText = "p_forfeit_text"
            }
        }
        struct CreatedRow: Decodable {
            let inviteCode: String
            enum CodingKeys: String, CodingKey { case inviteCode = "invite_code" }
        }
        do {
            let row: CreatedRow = try await supabase
                .rpc("create_duel_commitment", params: Parameters(
                    days: days, kind: commitment.rawValue,
                    stakeDays: stakeDays, forfeitText: forfeitText
                ))
                .execute()
                .value
            AnalyticsService.shared.track(.duelCreated, ["days": days, "commitment": commitment.rawValue])
            await load()
            return row.inviteCode
        } catch {
            logger.error("create_duel failed: \(error)")
            errorMessage = AppLanguage.current == "ru" ? "Не удалось создать дуэль" : "Couldn't create the duel"
            return nil
        }
    }

    func joinDuel(code: String) async -> Bool {
        struct JoinedRow: Decodable {
            let challengerId: UUID
            let days: Int
            enum CodingKeys: String, CodingKey {
                case challengerId = "challenger_id"
                case days
            }
        }
        do {
            let row: JoinedRow = try await supabase
                .rpc("join_duel_commitment", params: ["p_code": code.trimmingCharacters(in: .whitespacesAndNewlines)])
                .execute()
                .value
            AnalyticsService.shared.track(.duelJoined)
            let lang = await recipientLanguage(row.challengerId)
            let title = lang == "ru" ? "Вызов принят ⚔️" : "Challenge accepted ⚔️"
            let body = lang == "ru"
                ? "Соперник в игре: \(row.days) дн., начиная с сегодня. Не проиграй!"
                : "Your opponent is in: \(row.days) days, starting today. Don't lose!"
            await NotificationService.shared.sendPush(toUserId: row.challengerId, title: title, body: body)
            await load()
            return true
        } catch {
            logger.error("join_duel failed: \(error)")
            errorMessage = AppLanguage.current == "ru" ? "Код не найден или дуэль уже началась" : "Code not found, or the duel already started"
            return false
        }
    }

    func cancelDuel(_ duel: Duel) async {
        do {
            try await supabase
                .rpc("cancel_duel", params: ["p_duel_id": duel.id.uuidString])
                .execute()
            await load()
        } catch {
            logger.error("cancel_duel failed: \(error)")
            errorMessage = AppLanguage.current == "ru" ? "Не удалось отменить дуэль" : "Couldn't cancel the duel"
        }
    }
}
