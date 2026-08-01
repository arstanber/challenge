import SwiftUI

/// A data source the user can connect to auto-track a task's progress.
enum DataConnector: String, CaseIterable, Identifiable, Codable {
    // Free
    case appleHealth
    case appleFitness
    case appleCalendar
    case telegram
    case appleClock
    case appleShortcuts
    case chessCom
    case github
    case lichess
    case youtube
    // Max
    case strava

    var id: String { rawValue }

    enum Kind { case health, oauth, calendar, telegram, clock, shortcuts, username }

    /// Apple Health / Fitness are read on-device via HealthKit; Apple Calendar via EventKit;
    /// Telegram wraps `TelegramService`; the alarm clock is a local notification; the rest
    /// are OAuth2 web APIs.
    var kind: Kind {
        switch self {
        case .appleHealth, .appleFitness:                                  return .health
        case .appleCalendar:                                               return .calendar
        case .telegram:                                                    return .telegram
        case .appleClock:                                                  return .clock
        case .appleShortcuts:                                              return .shortcuts
        case .chessCom, .github, .lichess, .youtube:                       return .username
        case .strava:                                                      return .oauth
        }
    }

    /// Plan tier required to connect this source.
    var requiredPlan: UserPlan {
        switch self {
        case .appleHealth, .appleFitness, .appleCalendar, .telegram, .appleClock, .appleShortcuts, .chessCom, .github, .lichess, .youtube:
            return .free
        case .strava:
            return .max
        }
    }

    /// False while an OAuth app registration is missing (placeholder client ID
    /// in `OAuthSecrets`) -- such connectors are hidden from the UI instead of
    /// failing with a config error on tap. All current connectors are ready.
    var isConfigured: Bool { true }

    /// Whether a user on `plan` can connect this source.
    func isUnlocked(for plan: UserPlan) -> Bool {
        requiredPlan == .free || plan.hasMaxConnectors
    }

    var displayName: String {
        switch self {
        case .appleHealth:   return String(localized: "Apple Здоровье")
        case .appleFitness:  return String(localized: "Apple Фитнес")
        case .appleCalendar: return String(localized: "Календарь Apple")
        case .telegram:      return "Telegram"
        case .appleClock:    return String(localized: "Будильник")
        case .appleShortcuts: return String(localized: "Команды")
        case .chessCom:      return "Chess.com"
        case .github:        return "GitHub"
        case .lichess:       return "Lichess"
        case .youtube:       return "YouTube"
        case .strava:        return "Strava"
        }
    }

    /// One-line description of what connecting this source gives the user.
    var summary: String {
        switch self {
        case .appleHealth:   return String(localized: "Шаги, калории и тренировки из Apple Здоровье")
        case .appleFitness:  return String(localized: "Кольца активности и тренировки из Apple Фитнес")
        case .appleCalendar: return String(localized: "Учитывает события из календаря при планировании задач")
        case .telegram:      return String(localized: "Создавайте задачи и отправляйте фото-отчёты боту")
        case .appleClock:    return String(localized: "Ежедневное напоминание со списком задач в выбранное время")
        case .appleShortcuts: return String(localized: "Запускайте задачи и автоматизации через приложение «Команды» и Siri")
        case .chessCom:      return String(localized: "Засчитывает сыгранные за день партии на Chess.com")
        case .github:        return String(localized: "Засчитывает публичные коммиты за день")
        case .lichess:       return String(localized: "Засчитывает сыгранные за день партии на Lichess")
        case .youtube:       return String(localized: "Засчитывает опубликованные за день видео")
        case .strava:        return String(localized: "Пробежки и тренировки из Strava засчитываются автоматически")
        }
    }

    var icon: String {
        switch self {
        case .appleHealth:   return "heart.fill"
        case .appleFitness:  return "figure.run"
        case .appleCalendar: return "calendar"
        case .telegram:      return "paperplane.fill"
        case .appleClock:    return "alarm.fill"
        case .appleShortcuts: return "square.stack.3d.up.fill"
        case .chessCom:      return "checkerboard.rectangle"
        case .github:        return "chevron.left.forwardslash.chevron.right"
        case .lichess:       return "circle.grid.cross.fill"
        case .youtube:       return "play.rectangle.fill"
        case .strava:        return "figure.outdoor.cycle"
        }
    }

    /// Bundled brand logo (asset name) shown instead of the SF Symbol `icon`.
    /// Telegram and the alarm clock have no brand asset and fall back to `icon`.
    var logoAsset: String? {
        switch self {
        case .appleHealth:    return "applehealth"
        case .appleFitness:   return "applefitness"
        case .appleCalendar:  return "applecalendar"
        case .appleShortcuts: return "appleshortcuts"
        case .chessCom:       return "chess"
        case .strava:         return "strava"
        case .github, .lichess, .youtube, .telegram, .appleClock: return nil
        }
    }

    var tint: Color {
        switch self {
        case .appleHealth:   return Color(hex: "FF2D55")
        case .appleFitness:  return Color(hex: "2FB873")
        case .appleCalendar: return Color(hex: "FF3B30")
        case .telegram:      return Color(hex: "29A9EA")
        case .appleClock:    return Color(hex: "FF9F0A")
        case .appleShortcuts: return Color(hex: "5E5CE6")
        case .chessCom:      return Color(hex: "769656")
        case .github:        return Color.primary
        case .lichess:       return Color(hex: "B58863")
        case .youtube:       return Color(hex: "FF0000")
        case .strava:        return Color(hex: "FC4C02")
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
        case .unavailable:          return String(localized: "Эта функция недоступна на устройстве.")
        case .authorizationDenied:  return String(localized: "Доступ не предоставлен.")
        case .oauthCancelled:       return String(localized: "Подключение отменено.")
        case .oauthFailed:          return String(localized: "Не удалось подключить приложение.")
        case .notConfigured(let m): return m
        case .server(let m):        return m
        case .requiresMax:          return String(localized: "Доступно в reInspire Max")
        }
    }
}
