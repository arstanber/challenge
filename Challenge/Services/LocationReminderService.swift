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
    private var authContinuations: [CheckedContinuation<CLAuthorizationStatus, Never>] = []

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }
    var currentLocation: CLLocation? { manager.location }

    override private init() {
        super.init()
        manager.delegate = self
    }

    // MARK: - Authorization

    enum AuthResult {
        case granted
        /// Location permission denied or restricted.
        case locationDenied
        /// Notification permission denied (location triggers still fire notifications).
        case notificationsDenied
    }

    /// Requests notification permission, then location "When In Use"
    /// (enough to register location-notification triggers), and reports
    /// what is missing so the UI can point the user to system settings.
    func ensureAuthorized() async -> AuthResult {
        await NotificationService.shared.requestPermission()
        guard NotificationService.shared.permissionGranted else { return .notificationsDenied }

        var status = manager.authorizationStatus
        if status == .notDetermined {
            status = await withCheckedContinuation { continuation in
                authContinuations.append(continuation)
                manager.requestWhenInUseAuthorization()
            }
        }
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: return .granted
        default: return .locationDenied
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            // .notDetermined fires once on delegate attach -- not an answer yet.
            guard status != .notDetermined else { return }
            let continuations = self.authContinuations
            self.authContinuations.removeAll()
            for continuation in continuations { continuation.resume(returning: status) }
        }
    }

    // MARK: - Reminders

    private func identifier(for activityId: UUID) -> String { "geo_\(activityId.uuidString)" }

    /// Schedules a notification that fires when the user enters the region.
    func setReminder(activityId: UUID, title: String, coordinate: CLLocationCoordinate2D,
                     radius: CLLocationDistance = 150, placeName: String) async throws {
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
        content.body = "Вы рядом с \(placeName) -- самое время сделать задачу!"
        content.sound = .default

        let trigger = UNLocationNotificationTrigger(region: region, repeats: true)
        let request = UNNotificationRequest(identifier: identifier(for: activityId),
                                            content: content, trigger: trigger)
        do {
            try await UNUserNotificationCenter.current().add(request)
        } catch {
            logger.error("LocationReminder add error: \(error)")
            throw error
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
