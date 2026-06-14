import Foundation

/// Default-tone push-text pool -- the calm counterpart of `ZoomerCopy`.
/// Pools are split by time of day; `push(hour:streak:)` mixes the matching
/// slot with the always-appropriate general pool and, once a streak is
/// worth naming, the streak-praise variants.
enum StandardCopy {
    // MARK: - Time-of-day pools

    static let morning: [PushText] = [
        .init(title: "Новый день", body: "Новый шанс стать лучше. Начни прямо сейчас."),
        .init(title: "Доброе утро", body: "Сегодня -- ещё один день к твоей цели."),
        .init(title: "Каждое утро", body: "Ты выбираешь, кем становишься. Сделай задание."),
    ]

    static let daytime: [PushText] = [
        .init(title: "Ты справишься", body: "Одно маленькое действие меняет всё."),
        .init(title: "Не останавливайся", body: "Ты уже так далеко зашёл. Продолжай."),
        .init(title: "Просто сделай", body: "Через 5 минут будешь рад, что начал."),
        .init(title: "Твоя цель ждёт", body: "Один шаг сегодня -- большой результат завтра."),
    ]

    static let evening: [PushText] = [
        .init(title: "День ещё не закончился", body: "Успей выполнить задание до полуночи."),
        .init(title: "Ещё есть время", body: "Заверши день с гордостью за себя."),
        .init(title: "Сегодня считается", body: "Не дай этому дню пройти впустую."),
    ]

    /// Fits any hour.
    static let general: [PushText] = [
        .init(title: "Маленький прогресс", body: "Всё равно прогресс. Сделай сегодняшнее задание."),
        .init(title: "Ты можешь", body: "Просто открой приложение и начни."),
        .init(title: "Для себя", body: "Не для кого-то. Для лучшей версии себя."),
    ]

    /// Streak praise -- only when there is a real run to point at.
    static func streakPraise(streak: Int) -> [PushText] {
        [
            .init(title: "\(RuPlural.days(streak)) подряд", body: "Это не случайность -- это твоя работа. Продолжай."),
            .init(title: "Серия растёт", body: "Каждый день делает тебя сильнее."),
            .init(title: "Ты уже \(RuPlural.days(streak))", body: "Не останавливайся -- лучшее впереди."),
        ]
    }

    /// Candidates for a push firing around `hour` (task reminders, the
    /// personal-time nudge). `streak` is whatever run is most relevant to
    /// the caller: the task's own streak or the global one.
    static func pool(hour: Int, streak: Int) -> [PushText] {
        var pool = general
        switch hour {
        case ..<12:  pool += morning
        case 12..<18: pool += daytime
        default:     pool += evening
        }
        if streak >= 2 { pool += streakPraise(streak: streak) }
        return pool
    }

    static func push(hour: Int, streak: Int) -> PushText {
        pool(hour: hour, streak: streak).randomElement() ?? general[0]
    }
}
