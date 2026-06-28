import Foundation

/// Default-tone push-text pool -- the calm counterpart of `ZoomerCopy`.
/// Pools are split by time of day; `push(hour:streak:)` mixes the matching
/// slot with the always-appropriate general pool and, once a streak is
/// worth naming, the streak-praise variants.
enum StandardCopy {
    // MARK: - Time-of-day pools

    static let morning: [PushText] = [
        .init(title: String(localized: "Новый день"), body: String(localized: "Новый шанс стать лучше. Начни прямо сейчас.")),
        .init(title: String(localized: "Доброе утро"), body: String(localized: "Сегодня -- ещё один день к твоей цели.")),
        .init(title: String(localized: "Каждое утро"), body: String(localized: "Ты выбираешь, кем становишься. Сделай задание.")),
    ]

    static let daytime: [PushText] = [
        .init(title: String(localized: "Ты справишься"), body: String(localized: "Одно маленькое действие меняет всё.")),
        .init(title: String(localized: "Не останавливайся"), body: String(localized: "Ты уже так далеко зашёл. Продолжай.")),
        .init(title: String(localized: "Просто сделай"), body: String(localized: "Через 5 минут будешь рад, что начал.")),
        .init(title: String(localized: "Твоя цель ждёт"), body: String(localized: "Один шаг сегодня -- большой результат завтра.")),
    ]

    static let evening: [PushText] = [
        .init(title: String(localized: "День ещё не закончился"), body: String(localized: "Успей выполнить задание до полуночи.")),
        .init(title: String(localized: "Ещё есть время"), body: String(localized: "Заверши день с гордостью за себя.")),
        .init(title: String(localized: "Сегодня считается"), body: String(localized: "Не дай этому дню пройти впустую.")),
    ]

    /// Fits any hour.
    static let general: [PushText] = [
        .init(title: String(localized: "Маленький прогресс"), body: String(localized: "Всё равно прогресс. Сделай сегодняшнее задание.")),
        .init(title: String(localized: "Ты можешь"), body: String(localized: "Просто открой приложение и начни.")),
        .init(title: String(localized: "Для себя"), body: String(localized: "Не для кого-то. Для лучшей версии себя.")),
    ]

    /// Streak praise -- only when there is a real run to point at. Built
    /// from runtime data (the day count), so it branches on `AppLanguage`
    /// directly rather than going through the String Catalog.
    static func streakPraise(streak: Int) -> [PushText] {
        let days = Plural.days(streak)
        switch AppLanguage.current {
        case "ru":
            return [
                .init(title: "\(days) подряд", body: "Это не случайность -- это твоя работа. Продолжай."),
                .init(title: "Серия растёт", body: "Каждый день делает тебя сильнее."),
                .init(title: "Ты уже \(days)", body: "Не останавливайся -- лучшее впереди."),
            ]
        case "de":
            return [
                .init(title: "\(days) am Stück", body: "Das ist kein Zufall -- das ist deine Arbeit. Mach weiter."),
                .init(title: "Deine Serie wächst", body: "Jeder Tag macht dich stärker."),
                .init(title: "Schon \(days)", body: "Hör jetzt nicht auf -- das Beste kommt noch."),
            ]
        case "kk":
            return [
                .init(title: "\(days) қатарынан", body: "Бұл кездейсоқтық емес -- бұл сенің еңбегің. Жалғастыр."),
                .init(title: "Серияң өсіп келеді", body: "Әр күн сені күшейтеді."),
                .init(title: "Қазірдің өзінде \(days)", body: "Тоқтама -- ең жақсысы әлі алда."),
            ]
        case "fr":
            return [
                .init(title: "\(days) d'affilée", body: "Ce n'est pas de la chance -- c'est ton travail. Continue."),
                .init(title: "Ta série grandit", body: "Chaque jour te rend plus fort."),
                .init(title: "Déjà \(days)", body: "Ne t'arrête pas maintenant -- le meilleur est à venir."),
            ]
        case "ar":
            return [
                .init(title: "\(days) متتالية", body: "هذا ليس حظًا -- إنه مجهودك. واصل."),
                .init(title: "سلسلتك تنمو", body: "كل يوم يجعلك أقوى."),
                .init(title: "وصلت إلى \(days)", body: "لا تتوقف الآن -- الأفضل قادم."),
            ]
        default:
            return [
                .init(title: "\(days) in a row", body: "This isn't luck -- it's your work. Keep going."),
                .init(title: "Your streak is growing", body: "Every day makes you stronger."),
                .init(title: "You're already at \(days)", body: "Don't stop now -- the best is ahead."),
            ]
        }
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
