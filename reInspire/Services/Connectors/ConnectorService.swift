import Foundation
import Observation
import EventKit
#if canImport(UIKit)
import UIKit
#endif

/// Facade over every data source. Views talk only to this.
///
/// - Apple Health / Fitness → `HealthKitConnector` (on-device, fully functional).
/// - Apple Calendar → `CalendarConnector` (EventKit, on-device).
/// - Apple "smart alarm" → `ClockConnector` (local notifications).
/// - Telegram → wraps `TelegramService`'s existing link state; no separate connect flow.
/// - Strava → `OAuthConnector` (OAuth2 via the `connector-oauth` Supabase Edge
///   Function, which holds the client secrets and tokens).
/// - Chess.com → `ChessConnector` (public API by username, on-device, no OAuth).
@MainActor
@Observable
final class ConnectorService {
    static let shared = ConnectorService()

    /// Currently connected sources (drives the UI; persisted in UserDefaults).
    private(set) var connected: Set<DataConnector> = []

    private let health = HealthKitConnector()
    private let oauth = OAuthConnector()
    private let calendar = CalendarConnector()
    private let clock = ClockConnector()
    private let chess = ChessConnector()
    private let defaultsKey = "connected_connectors_v1"

    private init() { load() }

    /// Reports the REAL state, not just a stored flag, so a connector the user
    /// never set up (or revoked in iOS Settings) is never shown as connected.
    func isConnected(_ c: DataConnector) -> Bool {
        switch c {
        case .telegram:      return TelegramService.shared.isLinked
        case .appleClock:    return clock.isEnabled
        case .chessCom:      return chess.isConnected
        case .appleCalendar: return connected.contains(c) && Self.isCalendarAuthorized
        default:             return connected.contains(c)
        }
    }

    /// The stored Chess.com username (for prefilling the connect sheet).
    var chessUsername: String? { chess.username }

    /// Connect Chess.com by validating + storing a username (no OAuth).
    func connectChess(username: String) async throws {
        try await chess.connect(username: username)
        connected.insert(.chessCom)
        save()
    }

    func disconnectChess() {
        chess.disconnect()
        connected.remove(.chessCom)
        save()
    }

    private static var isCalendarAuthorized: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    // MARK: - Clock reminder (configurable time)

    /// Current reminder time as a Date today (for the time picker).
    var clockReminderTime: Date {
        Calendar.current.date(
            bySettingHour: clock.reminderHour, minute: clock.reminderMinute, second: 0, of: Date()
        ) ?? Date()
    }

    /// Enable/refresh the morning reminder at the chosen time.
    func enableClock(at date: Date) async throws {
        try await clock.enable(at: date)
        connected.insert(.appleClock)
        save()
    }

    func disableClock() {
        clock.disable()
        connected.remove(.appleClock)
        save()
    }

    /// Connect a source. Throws `ConnectorError` (incl. user-cancelled / not-configured /
    /// `.requiresMax` when the user's plan doesn't unlock this connector).
    func connect(_ c: DataConnector) async throws {
        let plan = AuthService.shared.currentUser?.plan ?? .free
        guard c.isUnlocked(for: plan) else { throw ConnectorError.requiresMax }

        switch c.kind {
        case .health:    try await health.requestAuthorization()
        case .oauth:     try await oauth.connect(c)
        case .calendar:  try await calendar.requestAuthorization()
        case .clock:     try await clock.enable()
        case .shortcuts: openShortcutsApp()
        case .username:  return // Chess.com etc. connect via their own sheet.
        case .telegram:  return // handled via TelegramLinkView; nothing to do here.
        }
        connected.insert(c)
        save()
    }

    func disconnect(_ c: DataConnector) async {
        switch c.kind {
        case .oauth:    await oauth.disconnect(c)
        case .clock:    clock.disable()
        case .username: chess.disconnect()
        case .telegram: return // handled via TelegramLinkView.
        case .health, .calendar, .shortcuts: break
        }
        connected.remove(c)
        save()
    }

    /// Opens the system Shortcuts app so the user can build automations on top
    /// of reInspire's App Intents (see AppIntents.swift).
    private func openShortcutsApp() {
        #if canImport(UIKit)
        if let url = URL(string: "shortcuts://") {
            UIApplication.shared.open(url)
        }
        #endif
    }

    /// Best available "today" value for the metric a task tracks, across connected sources.
    /// Apple Health wins when present; otherwise the first connected OAuth source that returns data.
    func todayValue(for activity: Activity) async -> Double? {
        // A task bound to a connector at creation reads exactly that source.
        if let bound = activity.connector {
            let metric = activity.connectorMetric ?? ConnectorMetric.infer(from: activity)
            return await boundValue(bound, metric: metric)
        }

        let metric = ConnectorMetric.infer(from: activity)
        if connected.contains(.appleHealth) || connected.contains(.appleFitness) {
            if let v = try? await health.todayValue(metric) { return v }
        }
        for c in connected where c.kind == .oauth {
            if let v = try? await oauth.todayValue(provider: c, metric: metric), v > 0 { return v }
        }
        // Chess.com games count toward "items today" tasks.
        if metric == .itemsToday && chess.isConnected {
            let games = await chess.gamesToday()
            if games > 0 { return Double(games) }
        }
        return nil
    }

    /// Today's value from one specific connector, or nil if it isn't connected
    /// or can't report this metric.
    private func boundValue(_ c: DataConnector, metric: ConnectorMetric) async -> Double? {
        guard isConnected(c) else { return nil }
        switch c {
        case .appleHealth, .appleFitness:
            return try? await health.todayValue(metric)
        case .strava:
            return try? await oauth.todayValue(provider: c, metric: metric)
        case .appleCalendar:
            return await todayCalendarEventsCount().map(Double.init)
        case .chessCom:
            return Double(await chess.gamesToday())
        case .telegram, .appleClock, .appleShortcuts:
            return nil
        }
    }

    /// Number of events on the user's Apple calendars today, if connected.
    func todayCalendarEventsCount() async -> Int? {
        guard connected.contains(.appleCalendar) else { return nil }
        return await calendar.todayEventsCount()
    }

    // MARK: - Persistence

    private func load() {
        let raw = UserDefaults.standard.array(forKey: defaultsKey) as? [String] ?? []
        connected = Set(raw.compactMap(DataConnector.init(rawValue:)))
    }

    private func save() {
        UserDefaults.standard.set(connected.map(\.rawValue), forKey: defaultsKey)
    }
}
