import Foundation
import Supabase
import PostgREST
import Observation
import os.log

private let logger = Logger(subsystem: "com.reinspire", category: "ReferralService")

/// Referral program client. The server owns all accounting
/// (20260612c_referrals.sql): codes, one-shot redemption, reward claims,
/// the every-10th-referral milestone, and the pro_until/bonus_freezes
/// counters on the users row.
@MainActor
@Observable
final class ReferralService {
    static let shared = ReferralService()

    struct Info: Decodable {
        struct Unclaimed: Decodable, Identifiable {
            let id: UUID
            enum CodingKeys: String, CodingKey { case id }
        }

        let code: String
        let total: Int
        let bonusFreezes: Int
        let unclaimed: [Unclaimed]

        enum CodingKeys: String, CodingKey {
            case code, total, unclaimed
            case bonusFreezes = "bonus_freezes"
        }
    }

    enum Reward: String {
        case pro3d, freeze
    }

    private(set) var info: Info?
    private(set) var isLoading = false
    var errorMessage: String?

    private init() {}

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            info = try await supabase.rpc("get_referral_info").execute().value
        } catch {
            logger.error("get_referral_info failed: \(error)")
            errorMessage = AppLanguage.current == "ru" ? "Не удалось загрузить данные" : "Couldn't load referral data"
        }
    }

    /// Redeem an invite code (one-shot per account). Grants this user
    /// 3 days of PRO server-side; notifies the referrer.
    func redeem(code: String) async -> Bool {
        struct Redeemed: Decodable {
            let referrerId: UUID
            let total: Int
            let milestone: Bool
            enum CodingKeys: String, CodingKey {
                case referrerId = "referrer_id"
                case total, milestone
            }
        }
        do {
            let result: Redeemed = try await supabase
                .rpc("redeem_referral_code", params: ["p_code": code.trimmingCharacters(in: .whitespacesAndNewlines)])
                .execute()
                .value
            AnalyticsService.shared.track(.referralRedeemed)
            let lang = await recipientLanguage(result.referrerId)
            let title = lang == "ru"
                ? (result.milestone ? "10 друзей -- месяц PRO! 🏆" : "+1 друг по твоему коду 🎉")
                : (result.milestone ? "10 friends -- a month of PRO! 🏆" : "+1 friend via your code 🎉")
            let body = lang == "ru"
                ? (result.milestone
                    ? "Юбилейный реферал: тебе начислено 30 дней PRO."
                    : "Друг присоединился. Забери награду: 3 дня PRO или заморозка.")
                : (result.milestone
                    ? "Milestone referral: you've earned 30 days of PRO."
                    : "A friend joined. Claim your reward: 3 days of PRO or a streak freeze.")
            await NotificationService.shared.sendPush(toUserId: result.referrerId, title: title, body: body)
            await AuthService.shared.refreshProfile()
            return true
        } catch {
            logger.error("redeem_referral_code failed: \(error)")
            errorMessage = AppLanguage.current == "ru" ? "Код не найден или уже использован" : "Code not found, or already used"
            return false
        }
    }

    /// Looks up another user's language for a cross-user push (the
    /// referrer, not the redeemer) -- mirrors `DuelService.recipientLanguage`.
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

    /// Claim one referral reward as PRO days or a streak freeze.
    func claim(_ referralId: UUID, reward: Reward) async {
        do {
            try await supabase
                .rpc("claim_referral_reward", params: [
                    "p_referral_id": referralId.uuidString,
                    "p_reward": reward.rawValue,
                ])
                .execute()
            AnalyticsService.shared.track(.referralRewardClaimed, ["reward": reward.rawValue])
            await AuthService.shared.refreshProfile()
            await load()
        } catch {
            logger.error("claim_referral_reward failed: \(error)")
            errorMessage = AppLanguage.current == "ru" ? "Не удалось получить награду" : "Couldn't claim the reward"
        }
    }
}
