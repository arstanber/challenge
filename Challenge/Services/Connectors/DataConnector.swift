import SwiftUI

/// A data source the user can connect to auto-track a task's progress.
enum DataConnector: String, CaseIterable, Identifiable, Codable {
    case appleHealth
    case appleFitness
    case strava
    case whoop

    var id: String { rawValue }

    enum Kind { case health, oauth }

    /// Apple Health / Fitness are read on-device via HealthKit; the rest are OAuth2 web APIs.
    var kind: Kind {
        switch self {
        case .appleHealth, .appleFitness: return .health
        default:                          return .oauth
        }
    }

    var displayName: String {
        switch self {
        case .appleHealth:  return "Здоровье"
        case .appleFitness: return "Фитнес"
        case .strava:       return "Strava"
        case .whoop:        return "Whoop"
        }
    }

    var icon: String {
        switch self {
        case .appleHealth:  return "heart.fill"
        case .appleFitness: return "figure.run"
        case .strava:       return "figure.outdoor.cycle"
        case .whoop:        return "waveform.path.ecg"
        }
    }

    var tint: Color {
        switch self {
        case .appleHealth:  return Color(hex: "FF2D55")
        case .appleFitness: return Color(hex: "2FB873")
        case .strava:       return Color(hex: "FC4C02")
        case .whoop:        return Color(hex: "D5212B")
        }
    }
}

/// The metric a task tracks, inferred from its title — decides what we read from a connector.
enum ConnectorMetric: String, Codable {
    case steps, activeEnergy, exerciseMinutes, distance

    static func infer(from activity: Activity) -> ConnectorMetric {
        let t = activity.title.lowercased()
        func has(_ words: [String]) -> Bool { words.contains { t.contains($0) } }
        if has(["шаг", "step"]) { return .steps }
        if has(["кал", "calor", "энерг", "energy"]) { return .activeEnergy }
        if has(["км", "киломе", "дистан", "distance", "бег", "run", "ходь", " walk", "велик", "ride", "cycl"]) { return .distance }
        if has(["трен", "workout", "упраж", "exercise", "минут", "minute", "актив"]) { return .exerciseMinutes }
        return .steps
    }
}

enum ConnectorError: LocalizedError {
    case unavailable
    case authorizationDenied
    case oauthCancelled
    case oauthFailed
    case notConfigured(String)
    case server(String)

    var errorDescription: String? {
        switch self {
        case .unavailable:          return "Эта функция недоступна на устройстве."
        case .authorizationDenied:  return "Доступ не предоставлен."
        case .oauthCancelled:       return "Подключение отменено."
        case .oauthFailed:          return "Не удалось подключить приложение."
        case .notConfigured(let m): return m
        case .server(let m):        return m
        }
    }
}
