import Foundation
import Observation

/// Facade over every data source. Views talk only to this.
///
/// - Apple Health / Fitness → `HealthKitConnector` (on-device, fully functional).
/// - Strava / Google Fit / Garmin / Whoop / Fitbit → `OAuthConnector` (OAuth2 via the
///   `connector-oauth` Supabase Edge Function, which holds the client secrets and tokens).
@Observable
final class ConnectorService {
    static let shared = ConnectorService()

    /// Currently connected sources (drives the UI; persisted in UserDefaults).
    private(set) var connected: Set<DataConnector> = []

    private let health = HealthKitConnector()
    private let oauth = OAuthConnector()
    private let defaultsKey = "connected_connectors_v1"

    private init() { load() }

    func isConnected(_ c: DataConnector) -> Bool { connected.contains(c) }

    /// Connect a source. Throws `ConnectorError` (incl. user-cancelled / not-configured).
    func connect(_ c: DataConnector) async throws {
        switch c.kind {
        case .health: try await health.requestAuthorization()
        case .oauth:  try await oauth.connect(c)
        }
        await MainActor.run {
            connected.insert(c)
            save()
        }
    }

    func disconnect(_ c: DataConnector) async {
        if c.kind == .oauth { await oauth.disconnect(c) }
        await MainActor.run {
            connected.remove(c)
            save()
        }
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

    // MARK: - Persistence

    private func load() {
        let raw = UserDefaults.standard.array(forKey: defaultsKey) as? [String] ?? []
        connected = Set(raw.compactMap(DataConnector.init(rawValue:)))
    }

    private func save() {
        UserDefaults.standard.set(connected.map(\.rawValue), forKey: defaultsKey)
    }
}
