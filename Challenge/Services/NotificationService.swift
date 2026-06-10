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
        content.title = NSLocalizedString("Don't forget!", comment: "")
        content.body = String(format: NSLocalizedString("Submit your report for %@", comment: ""), activity.title)
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

    // MARK: - Streak evening nudge

    /// One-shot reminder today at `hour` if the user hasn't kept their streak yet.
    /// Re-scheduled on every app open, so it only fires on days that are still incomplete.
    func scheduleStreakNudge(hour: Int = 20) {
        let id = "streak-nudge"
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let now = Date()
        let cal = Calendar.current
        guard let fireDate = cal.date(bySettingHour: hour, minute: 0, second: 0, of: now),
              fireDate > now else { return }

        let content = UNMutableNotificationContent()
        content.title = "Don't break your streak 🔥"
        content.body = "You still have tasks for today. Finish them before midnight!"
        content.sound = .default

        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    func cancelStreakNudge() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["streak-nudge"])
    }

    // MARK: - Weekly review

    /// Repeating weekly summary every Sunday at `hour`.
    func scheduleWeeklyReview(hour: Int = 18) {
        let id = "weekly-review"
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = "Your week in review 📊"
        content.body = "See how many tasks you crushed this week and plan the next one."
        content.sound = .default

        var comps = DateComponents()
        comps.weekday = 1 // Sunday
        comps.hour = hour
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
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
