import Foundation
import UIKit
import UserNotifications
import Supabase
import PostgREST
import Observation

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
            print("Notification permission error: \(error)")
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

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Don't forget!", comment: "")
        content.body = String(format: NSLocalizedString("Submit your report for %@", comment: ""), activity.title)
        content.sound = .default
        content.userInfo = ["activity_id": activity.id.uuidString]

        var components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        components.second = 0

        let repeats = activity.frequency == .daily || activity.frequency == .weekly
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
        let request = UNNotificationRequest(identifier: "reminder-\(activity.id)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancelReminder(for activityId: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["reminder-\(activityId)"])
    }

    func saveAPNSToken(_ token: Data, userId: UUID) async {
        let tokenString = token.map { String(format: "%02x", $0) }.joined()
        do {
            try await supabase
                .from("push_tokens")
                .upsert(["user_id": userId.uuidString, "apns_token": tokenString], onConflict: "user_id")
                .execute()
        } catch {
            print("Failed to save APNs token: \(error)")
        }
    }
}
