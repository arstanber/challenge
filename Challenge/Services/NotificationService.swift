import Foundation
import UIKit
import UserNotifications
import Supabase
import PostgREST
import Observation
import os.log

private let notifLogger = Logger(subsystem: "com.challenge", category: "NotificationService")

@Observable
final class NotificationService: NSObject {
    static let shared = NotificationService()

    var permissionGranted = false

    private override init() {
        super.init()
        checkPermission()
    }

    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            permissionGranted = granted
            if granted { await registerForRemoteNotifications() }
        } catch {
            notifLogger.error("Notification permission error: \(error)")
        }
    }

    private func checkPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.permissionGranted = settings.authorizationStatus == .authorized
            }
        }
    }

    @MainActor
    private func registerForRemoteNotifications() async {
        #if !targetEnvironment(simulator)
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }

    func scheduleLocalReminder(for activity: Activity) {
        guard let reminderTime = activity.reminderTime else { return }
        // Replace any previously scheduled variant (frequency/days may have changed).
        cancelReminder(for: activity.id)

        let content = UNMutableNotificationContent()
        if AppPrefs.zoomerMode {
            let pick = ZoomerCopy.taskReminder(createdAt: activity.createdAt)
            content.title = pick.title
            content.subtitle = "«\(activity.title)»"
            content.body = pick.body
        } else {
            content.title = NSLocalizedString("Don't forget!", comment: "")
            content.body = String(format: NSLocalizedString("Submit your report for %@", comment: ""), activity.title)
        }
        content.sound = .default
        content.userInfo = ["activity_id": activity.id.uuidString]

        var components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        components.second = 0

        let center = UNUserNotificationCenter.current()
        if activity.frequency == .weekly, let days = activity.scheduleDays, !days.isEmpty {
            // One repeating request per scheduled weekday.
            // schedule_days is ISO (Mon=1..Sun=7); DateComponents.weekday is Sun=1..Sat=7.
            for iso in days {
                var comps = components
                comps.weekday = iso == 7 ? 1 : iso + 1
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                let request = UNNotificationRequest(identifier: "reminder-\(activity.id)-\(iso)", content: content, trigger: trigger)
                center.add(request)
            }
        } else {
            let repeats = activity.frequency == .daily || activity.frequency == .weekly
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
            let request = UNNotificationRequest(identifier: "reminder-\(activity.id)", content: content, trigger: trigger)
            center.add(request)
        }
    }

    func cancelReminder(for activityId: UUID) {
        // Legacy un-suffixed identifier plus the 7 per-weekday variants.
        let ids = ["reminder-\(activityId)"] + (1...7).map { "reminder-\(activityId)-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Bulk reminder sync

    /// Re-schedule per-task reminders for every active activity that has a reminder time.
    func syncReminders(for activities: [Activity]) {
        for activity in activities where activity.status == .active && activity.reminderTime != nil {
            scheduleLocalReminder(for: activity)
        }
    }

    // MARK: - Streak risk nudges

    /// Evening streak-protection pushes with concrete numbers: a warning at
    /// 20:00 and a last call at 22:30, today only. Scheduled only while there
    /// is a real streak to lose (`streak >= 1`) and the 75% day goal is not
    /// met yet (`tasksToSave >= 1`). Re-scheduled on every app open and on
    /// every completion, so the numbers stay honest; silent on closed days.
    func scheduleStreakNudge(streak: Int, tasksToSave: Int) {
        cancelStreakNudge()
        guard streak >= 1, tasksToSave >= 1 else { return }

        let remaining = Self.remainingPhrase(tasksToSave)
        if AppPrefs.zoomerMode {
            // Rotating meme intro, but the concrete numbers stay: the whole
            // point of the evening pushes is "what exactly do I lose tonight".
            let pick = ZoomerCopy.streakRisk(streak: streak)
            scheduleOnceToday(
                id: "streak-nudge", hour: 20, minute: 0,
                title: pick.title,
                body: "\(pick.body) До полуночи \(remaining)."
            )
            scheduleOnceToday(
                id: "streak-nudge-final", hour: 22, minute: 30,
                title: "🚨 Вообще не рофл: стрик \(streak) дн.",
                body: "Полтора часа и день закрыт навсегда. Ещё успеваешь: \(remaining). Погнали!"
            )
        } else {
            scheduleOnceToday(
                id: "streak-nudge", hour: 20, minute: 0,
                title: "🔥 Серия \(streak) дн. сгорит в полночь",
                body: "Чтобы день засчитался, \(remaining). Закрой до 00:00, и серия живёт."
            )
            scheduleOnceToday(
                id: "streak-nudge-final", hour: 22, minute: 30,
                title: "🚨 Последний шанс: серия \(streak) дн.",
                body: "Через полтора часа день закроется навсегда. Ещё успеваешь: \(remaining)."
            )
        }
    }

    func cancelStreakNudge() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: ["streak-nudge", "streak-nudge-final"])
    }

    /// One-shot notification today at `hour:minute`; skipped if that moment
    /// has already passed.
    private func scheduleOnceToday(id: String, hour: Int, minute: Int, title: String, body: String) {
        let now = Date()
        let cal = Calendar.current
        guard let fireDate = cal.date(bySettingHour: hour, minute: minute, second: 0, of: now),
              fireDate > now else { return }

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        UNUserNotificationCenter.current()
            .add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    /// "осталась 1 задача" / "осталось 2 задачи" / "осталось 5 задач".
    private static func remainingPhrase(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return "осталась \(n) задача" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "осталось \(n) задачи" }
        return "осталось \(n) задач"
    }

    // MARK: - Personal-time nudge

    /// One repeating daily reminder at the time the user usually completes
    /// tasks (median report minute, computed by TaskEngine). Morning and
    /// afternoon only: evenings belong to the streak-risk pushes, and two
    /// pushes about the same thing within an hour train people to ignore both.
    func schedulePersonalNudge(minuteOfDay: Int?, streak: Int) {
        let id = "personal-nudge"
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard let minuteOfDay, (8 * 60)...(19 * 60) ~= minuteOfDay else { return }

        let content = UNMutableNotificationContent()
        if AppPrefs.zoomerMode {
            let pick = ZoomerCopy.personalNudge(streak: streak)
            content.title = pick.title
            content.body = pick.body
        } else {
            content.title = "Твоё обычное время 🎯"
            content.body = "Обычно ты закрываешь задачи примерно сейчас. Один отчёт, и день уже не зря."
        }
        content.sound = .default

        var comps = DateComponents()
        comps.hour = minuteOfDay / 60
        comps.minute = minuteOfDay % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: - Weekly review

    /// Repeating weekly summary every Sunday at `hour`.
    func scheduleWeeklyReview(hour: Int = 18) {
        let id = "weekly-review"
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        if AppPrefs.zoomerMode {
            content.title = "Недельный рекап 📊"
            content.body = "Глянь, сколько ты затащил за неделю. Спойлер: есть чем флексить (или нет)."
        } else {
            content.title = "Твоя неделя в цифрах 📊"
            content.body = "Посмотри, сколько задач закрыто за неделю, и спланируй следующую."
        }
        content.sound = .default

        var comps = DateComponents()
        comps.weekday = 1 // Sunday
        comps.hour = hour
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: - Legacy cleanup

    /// The 15-per-day motivation plan is retired: generic pushes train users
    /// to swipe away everything, including the streak-risk push that matters.
    /// Installed devices still carry its daily-repeating requests, so clear
    /// them once per launch until the fleet rolls over.
    func clearLegacyMotivationPlan() {
        let ids = (0..<20).flatMap { ["plan-slot-\($0)", "plan-extra-\($0)"] }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Send remote push via edge function

    /// Sends a push notification to any user by their Supabase user_id.
    /// Requires APNS_* secrets configured in Supabase → Edge Functions → Secrets.
    func sendPush(toUserId userId: UUID, title: String, body: String, data: [String: String]? = nil) async {
        struct PushRequest: Encodable {
            let user_id: String
            let title: String
            let body: String
            let data: [String: String]?
        }
        let payload = PushRequest(
            user_id: userId.uuidString,
            title: title,
            body: body,
            data: data
        )
        struct PushResult: Decodable { let ok: Bool? }
        do {
            let _: PushResult = try await supabase.functions
                .invoke("send-push", options: FunctionInvokeOptions(body: payload))
        } catch {
            notifLogger.error("sendPush failed: \(error)")
        }
    }

    func saveAPNSToken(_ token: Data, userId: UUID) async {
        let tokenString = token.map { String(format: "%02x", $0) }.joined()
        do {
            try await supabase
                .from("push_tokens")
                .upsert(["user_id": userId.uuidString, "apns_token": tokenString], onConflict: "user_id")
                .execute()
        } catch {
            notifLogger.error("Failed to save APNs token: \(error)")
        }
    }
}
