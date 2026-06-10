import Foundation
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.challenge", category: "ClockConnector")

/// "Smart morning reminder" -- a daily local notification at 08:00 that nudges the
/// user to start today's first task. Connecting requests notification permission
/// and schedules the repeating reminder; disconnecting cancels it.
@MainActor
final class ClockConnector {
    static let notificationId = "clock-connector-morning"
    private static let defaultsKey = "clock_connector_enabled_v1"

    /// Whether the morning reminder is currently enabled (persisted).
    var isEnabled: Bool {
        UserDefaults.standard.bool(forKey: Self.defaultsKey)
    }

    /// Requests notification permission and schedules the daily 08:00 reminder.
    func enable() async throws {
        let granted = try await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .badge, .sound])
        guard granted else { throw ConnectorError.authorizationDenied }

        scheduleMorningReminder()
        UserDefaults.standard.set(true, forKey: Self.defaultsKey)
    }

    /// Cancels the daily reminder.
    func disable() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.notificationId])
        UserDefaults.standard.set(false, forKey: Self.defaultsKey)
    }

    /// Schedules (or refreshes) the repeating 08:00 reminder using today's pending task count.
    func scheduleMorningReminder(hour: Int = 8, minute: Int = 0) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [Self.notificationId])

        let count = TaskEngine.shared.pendingTodayCount
        let content = UNMutableNotificationContent()
        content.title = "Доброе утро!"
        content.body = count > 0
            ? "Сегодня \(count) задач(и) -- начни с первой"
            : "Сегодня нет задач -- отличный день для отдыха"
        content.sound = .default

        var comps = DateComponents()
        comps.hour = hour
        comps.minute = minute
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        let request = UNNotificationRequest(identifier: Self.notificationId, content: content, trigger: trigger)
        center.add(request) { error in
            if let error {
                logger.error("Failed to schedule morning reminder: \(error)")
            }
        }
    }
}
