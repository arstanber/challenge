import Foundation
import Observation

/// Facade over every data source. Views talk only to this.
///
/// - Apple Health / Fitness → `HealthKitConnector` (on-device, fully functional).
/// - Apple Calendar → `CalendarConnector` (EventKit, on-device).
/// - Apple "smart alarm" → `ClockConnector` (local notifications).
/// - Telegram → wraps `TelegramService`'s existing link state; no separate connect flow.
/// - Strava / Whoop / Notion / Google Calendar/Docs/Drive/Gmail → `OAuthConnector` (OAuth2 via
///   the `connector-oauth` Supabase Edge Function, which holds the client secrets and tokens).
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
    private let defaultsKey = "connected_connectors_v1"

    private init() { load() }

    func isConnected(_ c: DataConnector) -> Bool {
        if c == .telegram { return TelegramService.shared.isLinked }
        return connected.contains(c)
    }

    /// Connect a source. Throws `ConnectorError` (incl. user-cancelled / not-configured /
    /// `.requiresMax` when the user's plan doesn't unlock this connector).
    func connect(_ c: DataConnector) async throws {
        let plan = AuthService.shared.currentUser?.plan ?? .free
        guard c.isUnlocked(for: plan) else { throw ConnectorError.requiresMax }

        switch c.kind {
        case .health:   try await health.requestAuthorization()
        case .oauth:    try await oauth.connect(c)
        case .calendar: try await calendar.requestAuthorization()
        case .clock:    try await clock.enable()
        case .telegram: return // handled via TelegramLinkView; nothing to do here.
        }
        connected.insert(c)
        save()
    }

    func disconnect(_ c: DataConnector) async {
        switch c.kind {
        case .oauth:    await oauth.disconnect(c)
        case .clock:    clock.disable()
        case .telegram: return // handled via TelegramLinkView.
        case .health, .calendar: break
        }
        connected.remove(c)
        save()
    }

    /// Best available "today" value for the metric a task tracks, across connected sources.
    /// Apple Health wins when present; otherwise the first connected OAuth source that returns data.
    func todayValue(for activity: Activity) async -> Double? {
        let metric = ConnectorMetric.infer(from: activity)
        if connected.contains(.appleHealth) || connected.contains(.appleFitness) {
            if let v = try? await health.todayValue(metric) { return v }
        }
        for c in connected where c.kind == .oauth {
            if let v = try? await oauth.todayValue(provider: c, metric: metric), v > 0 { return v }
        }
        return nil
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
