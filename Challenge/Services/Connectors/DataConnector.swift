import SwiftUI

/// A data source the user can connect to auto-track a task's progress.
enum DataConnector: String, CaseIterable, Identifiable, Codable {
    // Free
    case appleHealth
    case appleFitness
    case appleCalendar
    case googleCalendar
    case telegram
    case appleClock
    // Max
    case strava
    case whoop
    case notion
    case googleDocs
    case googleDrive
    case gmail

    var id: String { rawValue }

    enum Kind { case health, oauth, calendar, telegram, clock }

    /// Apple Health / Fitness are read on-device via HealthKit; Apple Calendar via EventKit;
    /// Telegram wraps `TelegramService`; the alarm clock is a local notification; the rest
    /// are OAuth2 web APIs.
    var kind: Kind {
        switch self {
        case .appleHealth, .appleFitness:                                  return .health
        case .appleCalendar:                                               return .calendar
        case .telegram:                                                    return .telegram
        case .appleClock:                                                  return .clock
        case .strava, .whoop, .notion, .googleCalendar, .googleDocs,
             .googleDrive, .gmail:                                         return .oauth
        }
    }

    /// Plan tier required to connect this source.
    var requiredPlan: UserPlan {
        switch self {
        case .appleHealth, .appleFitness, .appleCalendar, .googleCalendar, .telegram, .appleClock:
            return .free
        case .strava, .whoop, .notion, .googleDocs, .googleDrive, .gmail:
            return .max
        }
    }

    /// False while the OAuth app registration is missing (placeholder client
    /// ID in `OAuthSecrets`) -- such connectors are hidden from the UI
    /// instead of failing with a config error on tap.
    var isConfigured: Bool {
        switch self {
        case .whoop:  return !OAuthSecrets.whoop.hasPrefix("<")
        case .notion: return !OAuthSecrets.notion.hasPrefix("<")
        default:      return true
        }
    }

    /// Whether a user on `plan` can connect this source.
    func isUnlocked(for plan: UserPlan) -> Bool {
        requiredPlan == .free || plan.hasMaxConnectors
    }

    var displayName: String {
        switch self {
        case .appleHealth:   return "Здоровье"
        case .appleFitness:  return "Фитнес"
        case .appleCalendar: return "Календарь Apple"
        case .googleCalendar: return "Google Календарь"
        case .telegram:      return "Telegram"
        case .appleClock:    return "Будильник"
        case .strava:        return "Strava"
        case .whoop:         return "Whoop"
        case .notion:        return "Notion"
        case .googleDocs:    return "Google Документы"
        case .googleDrive:   return "Google Диск"
        case .gmail:         return "Gmail"
        }
    }

    /// One-line description of what connecting this source gives the user.
    var summary: String {
        switch self {
        case .appleHealth:   return "Шаги, калории и тренировки из Apple Здоровье"
        case .appleFitness:  return "Кольца активности и тренировки из Apple Фитнес"
        case .appleCalendar: return "Учитывает события из календаря при планировании задач"
        case .googleCalendar: return "Синхронизирует события Google Календаря с заданиями"
        case .telegram:      return "Создавайте задачи и отправляйте фото-отчёты боту"
        case .appleClock:    return "Утреннее напоминание со списком задач на день"
        case .strava:        return "Пробежки и тренировки из Strava засчитываются автоматически"
        case .whoop:         return "Восстановление и нагрузка из Whoop"
        case .notion:        return "Отмечайте задачи прямо в своих страницах Notion"
        case .googleDocs:    return "Учитывает изменения в документах Google за день"
        case .googleDrive:   return "Учитывает изменения файлов на Google Диске за день"
        case .gmail:         return "Считает входящие письма за сегодня"
        }
    }

    var icon: String {
        switch self {
        case .appleHealth:   return "heart.fill"
        case .appleFitness:  return "figure.run"
        case .appleCalendar: return "calendar"
        case .googleCalendar: return "calendar.badge.clock"
        case .telegram:      return "paperplane.fill"
        case .appleClock:    return "alarm.fill"
        case .strava:        return "figure.outdoor.cycle"
        case .whoop:         return "waveform.path.ecg"
        case .notion:        return "doc.text.fill"
        case .googleDocs:    return "doc.richtext.fill"
        case .googleDrive:   return "tray.full.fill"
        case .gmail:         return "envelope.fill"
        }
    }

    var tint: Color {
        switch self {
        case .appleHealth:   return Color(hex: "FF2D55")
        case .appleFitness:  return Color(hex: "2FB873")
        case .appleCalendar: return Color(hex: "FF3B30")
        case .googleCalendar: return Color(hex: "4285F4")
        case .telegram:      return Color(hex: "29A9EA")
        case .appleClock:    return Color(hex: "FF9F0A")
        case .strava:        return Color(hex: "FC4C02")
        case .whoop:         return Color(hex: "D5212B")
        case .notion:        return Color(hex: "000000")
        case .googleDocs:    return Color(hex: "4285F4")
        case .googleDrive:   return Color(hex: "34A853")
        case .gmail:         return Color(hex: "EA4335")
        }
    }
}

/// The metric a task tracks, inferred from its title — decides what we read from a connector.
enum ConnectorMetric: String, Codable {
    case steps, activeEnergy, exerciseMinutes, distance
    /// Number of items "today" — calendar events, modified docs/files, unread emails, etc.
    case itemsToday

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
    case requiresMax

    var errorDescription: String? {
        switch self {
        case .unavailable:          return "Эта функция недоступна на устройстве."
        case .authorizationDenied:  return "Доступ не предоставлен."
        case .oauthCancelled:       return "Подключение отменено."
        case .oauthFailed:          return "Не удалось подключить приложение."
        case .notConfigured(let m): return m
        case .server(let m):        return m
        case .requiresMax:          return "Доступно в Challenge Max"
        }
    }
}
