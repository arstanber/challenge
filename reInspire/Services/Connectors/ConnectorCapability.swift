import Foundation

/// One trackable thing a connector can do, phrased for the task-creation picker.
///
/// When the user types a connector name while creating a task (e.g. "Chess.com")
/// we surface its capabilities ("Сыгранные партии"); picking one turns the task
/// into an auto-verified goal with the matching metric, unit and a numeric target.
struct ConnectorCapability: Identifiable, Hashable {
    let connector: DataConnector
    /// What gets counted, in the user's language (e.g. "Сыгранные партии").
    let title: String
    /// What we actually read from the connector each day.
    let metric: ConnectorMetric
    /// Unit for the target field, e.g. "партий", "шагов", "км".
    let unit: String
    /// Sensible starting target prefilled into the goal field.
    let defaultTarget: Double

    var id: String { "\(connector.rawValue).\(metric.rawValue)" }

    /// Increment for the target stepper, scaled to the metric.
    var targetStep: Double {
        switch metric {
        case .steps:           return 500
        case .activeEnergy:    return 50
        case .distance:        return 1
        case .exerciseMinutes: return 5
        case .itemsToday:      return 1
        }
    }

    /// A ready-made task title, e.g. "Сыграть 10 партий" (target filled in by the VM).
    func taskTitle(target: Double) -> String {
        let n = Int(target)
        switch connector {
        case .chessCom:    return "Сыграть \(n) партий на Chess.com"
        case .appleHealth, .appleFitness:
            switch metric {
            case .steps:           return "Пройти \(n) шагов"
            case .activeEnergy:    return "Сжечь \(n) ккал"
            case .distance:        return "Пройти \(n) км"
            case .exerciseMinutes: return "Тренироваться \(n) минут"
            case .itemsToday:      return title
            }
        case .strava:      return "Преодолеть \(n) км в Strava"
        case .appleCalendar: return "Провести \(n) событий за день"
        default:           return title
        }
    }
}

extension DataConnector {
    /// Extra search terms so typing "chess", "шахматы" or "chess.com" all find
    /// Chess.com in the creation picker.
    var searchAliases: [String] {
        switch self {
        case .appleHealth:   return ["здоровье", "health", "apple health", "шаги", "steps", "калории", "apple"]
        case .appleFitness:  return ["фитнес", "fitness", "apple fitness", "тренировк", "кольца", "rings"]
        case .appleCalendar: return ["календарь", "calendar", "события", "events", "apple"]
        case .telegram:      return ["telegram", "телеграм", "бот"]
        case .appleClock:    return ["будильник", "alarm", "clock", "подъём", "apple"]
        case .appleShortcuts: return ["команды", "shortcuts", "siri", "автоматизац", "apple"]
        case .chessCom:      return ["chess", "chess.com", "chesscom", "шахмат", "шахматы"]
        case .strava:        return ["strava", "страва", "бег", "run", "велосипед", "ride"]
        }
    }

    /// Quantifiable, auto-trackable capabilities this connector exposes. Sources
    /// that only send reminders or run automations (Clock, Telegram, Shortcuts)
    /// have none -- they can't produce a per-day number.
    var capabilities: [ConnectorCapability] {
        switch self {
        case .appleHealth:
            return [
                ConnectorCapability(connector: self, title: "Шаги за день", metric: .steps, unit: "шагов", defaultTarget: 8000),
                ConnectorCapability(connector: self, title: "Активные калории", metric: .activeEnergy, unit: "ккал", defaultTarget: 500),
                ConnectorCapability(connector: self, title: "Дистанция за день", metric: .distance, unit: "км", defaultTarget: 5)
            ]
        case .appleFitness:
            return [
                ConnectorCapability(connector: self, title: "Минуты тренировки", metric: .exerciseMinutes, unit: "мин", defaultTarget: 30)
            ]
        case .strava:
            return [
                ConnectorCapability(connector: self, title: "Дистанция за день", metric: .distance, unit: "км", defaultTarget: 5)
            ]
        case .appleCalendar:
            return [
                ConnectorCapability(connector: self, title: "События в календаре за день", metric: .itemsToday, unit: "событий", defaultTarget: 1)
            ]
        case .chessCom:
            return [
                ConnectorCapability(connector: self, title: "Сыгранные партии за день", metric: .itemsToday, unit: "партий", defaultTarget: 10)
            ]
        case .telegram, .appleClock, .appleShortcuts:
            return []
        }
    }
}

extension ConnectorCapability {
    /// Every capability across configured connectors, in connector order.
    static var all: [ConnectorCapability] {
        DataConnector.allCases.filter { $0.isConfigured }.flatMap { $0.capabilities }
    }

    /// Capabilities whose connector is mentioned in `text` -- either the user is
    /// typing a connector name ("chess.c") or wrote a line that names it
    /// ("сыграть в шахматы"). Returns [] for short/no-match text so we never
    /// surface the whole list unprompted.
    static func detect(in text: String) -> [ConnectorCapability] {
        let q = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard q.count >= 3 else { return [] }
        return all.filter { cap in
            let tokens = cap.connector.searchAliases + [cap.connector.displayName.lowercased()]
            return tokens.contains { token in
                token.count >= 3 && (q.contains(token) || token.contains(q))
            }
        }
    }
}
