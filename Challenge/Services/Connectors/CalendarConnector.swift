import Foundation
import EventKit
import os.log

private let logger = Logger(subsystem: "com.challenge", category: "CalendarConnector")

/// Reads today's events from the user's Apple calendars via EventKit.
/// Read-only. Requires `NSCalendarsFullAccessUsageDescription`.
final class CalendarConnector {
    private let store = EKEventStore()

    /// Presents the system Calendar permission sheet (iOS 17+ full-access API).
    func requestAuthorization() async throws {
        do {
            let granted = try await store.requestFullAccessToEvents()
            guard granted else { throw ConnectorError.authorizationDenied }
        } catch let error as ConnectorError {
            throw error
        } catch {
            logger.error("Calendar authorization failed: \(error)")
            throw ConnectorError.authorizationDenied
        }
    }

    /// Number of events on the user's calendars that start today.
    func todayEventsCount() async -> Int {
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: Date())
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return 0 }

        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate).count
    }
}
