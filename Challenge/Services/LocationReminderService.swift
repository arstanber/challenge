import Foundation
import CoreLocation
import UserNotifications
import os.log

private let logger = Logger(subsystem: "com.challenge", category: "LocationReminderService")

// MARK: - Location Reminder Service (#10)
// Schedules geofence-triggered local notifications ("remind me when I arrive").

@MainActor
final class LocationReminderService: NSObject, CLLocationManagerDelegate {
    static let shared = LocationReminderService()

    private let manager = CLLocationManager()
    private let defaults = UserDefaults(suiteName: WidgetDataStore.appGroup) ?? .standard

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    override private init() {
        super.init()
        manager.delegate = self
    }

    // MARK: - Authorization

    func requestAuthorization() {
        // "When In Use" is enough to register location-notification triggers.
        manager.requestWhenInUseAuthorization()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}

    // MARK: - Reminders

    private func identifier(for activityId: UUID) -> String { "geo_\(activityId.uuidString)" }

    /// Schedules a notification that fires when the user enters the region.
    func setReminder(activityId: UUID, title: String, coordinate: CLLocationCoordinate2D,
                     radius: CLLocationDistance = 150, placeName: String) {
        let center = CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let region = CLCircularRegion(
            center: center,
            radius: min(max(radius, 100), 1000),
            identifier: identifier(for: activityId)
        )
        region.notifyOnEntry = true
        region.notifyOnExit = false

        let content = UNMutableNotificationContent()
        content.title = "📍 \(title)"
        content.body = "You're near \(placeName) — time to get it done!"
        content.sound = .default

        let trigger = UNLocationNotificationTrigger(region: region, repeats: true)
        let request = UNNotificationRequest(identifier: identifier(for: activityId),
                                            content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request) { error in
            if let error { logger.error("LocationReminder add error: \(error)") }
        }

        // Persist a marker so UI can show "reminder set"
        defaults.set(placeName, forKey: identifier(for: activityId))
    }

    func removeReminder(activityId: UUID) {
        let id = identifier(for: activityId)
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
        defaults.removeObject(forKey: id)
    }

    func reminderPlaceName(for activityId: UUID) -> String? {
        defaults.string(forKey: identifier(for: activityId))
    }
}
