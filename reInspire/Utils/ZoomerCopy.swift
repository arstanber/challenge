import Foundation

/// Push-text pool for zoomer mode (`AppPrefs.zoomerMode`). See `PushText`
/// for the rotation mechanics; `StandardCopy` is the default-tone twin.
enum ZoomerCopy {
    // MARK: - General motivation -- task reminders and the personal-time nudge

    static let motivation: [PushText] = [
        .init(title: "Это не цитата. Это режим.", body: "Дисциплина > мотивация. Всегда."),
        .init(title: "Productive era не ждёт", body: "Ты сейчас на пике. Не сломай это."),
        .init(title: "Glow up era началась", body: "Villain era отменяется. Сегодня ты растёшь."),
        .init(title: "Stay hard -- это сейчас", body: "Не завтра. Не через час. Сейчас."),
        .init(title: "Один процент в день", body: "За год -- другой человек. Сегодня твой 1%."),
        .init(title: "Это твой момент", body: "Не завтра, не в понедельник. Прямо сейчас."),
        .init(title: "Лучшая версия себя ждёт", body: "Она не придёт сама -- ты идёшь к ней каждый день."),
        .init(title: "История пишется сейчас", body: "Через год ты вспомнишь этот день. Что ты сделал?"),
        .init(title: "Тот пингвин пошёл в горы один", body: "Не знал, выживет ли. Пошёл всё равно. Ты можешь сделать одно задание."),
        .init(title: "Пингвин не спрашивал зачем", body: "Он просто шёл. Открой приложение и сделай то же самое."),
        .init(title: "Все остальные пингвины остались у океана", body: "Ты не все остальные. Докажи это."),
        .init(title: "+67 ауры", body: "За выполненное задание. Не упускай момент."),
        .init(title: "Do it for who you're becoming", body: "Не для результата. Для себя будущего. Открой приложение."),
        .init(title: "Hard days build strong people", body: "Сегодня тяжело? Именно поэтому -- сделай."),
        .init(title: "Silence. Discipline. Results.", body: "Без объяснений. Просто отметь задание."),
        .init(title: "Your future self is watching", body: "Он либо скажет спасибо. Либо нет. Выбор сейчас."),
        .init(title: "It's not about motivation. It's about showing up.", body: "Каждый день. Даже сегодня."),
        .init(title: "You owe it to yourself", body: "Не другим. Себе. Сделай задание."),
        .init(title: "The person you want to be is built today", body: "Не в понедельник. Не с нового года. Сейчас."),
        .init(title: "Train your mind like you train your body", body: "Один пропуск -- и мышца слабеет. Не пропускай."),
    ]

    /// Reminder copy for one task; the shared pool plus a variant built
    /// from the goal's creation date ("Тот ты верил в тебя").
    static func taskReminder(createdAt: Date) -> PushText {
        var pool = motivation
        pool.append(.init(
            title: "Тот ты верил в тебя",
            body: "Ты поставил цель \(dayFormatter.string(from: createdAt)). Оправдай доверие."
        ))
        return pool.randomElement() ?? motivation[0]
    }

    /// Personal-time nudge; no streak unlocks the "could have been 67" guilt trip.
    static func personalNudge(streak: Int) -> PushText {
        var pool = motivation
        if streak == 0 {
            pool.append(.init(
                title: "67 дней мог быть твой streak",
                body: "Но что-то пошло не так. Начни снова сегодня."
            ))
        }
        return pool.randomElement() ?? motivation[0]
    }

    // MARK: - Evening streak risk (caller appends the concrete numbers)

    static func streakRisk(streak: Int) -> PushText {
        var pool: [PushText] = [
            .init(title: "WE ARE SO BACK 🔥", body: "\(RuPlural.days(streak)) подряд. Серия не останавливается."),
            .init(title: "Один шаг решает всё", body: "Один пропуск -- it's over. Один отчёт -- we're back."),
            .init(title: "Не fumble свой streak", body: "2027 не твой год спасения. Сделай сейчас."),
            .init(title: "Я клубника ты клубника", body: "А почему у нас такой плохой стрик? Исправляй."),
            .init(title: "Rest if you must. But don't quit.", body: "Streak ждёт. Одно действие -- и ты снова в игре."),
            .init(title: "Small steps. Every day. No excuses.", body: "\(RuPlural.days(streak)) позади. Добавь ещё один."),
        ]
        if streak < 67 {
            pool.append(.init(
                title: "До 67-дневного streak \(RuPlural.remainingDays(67 - streak))",
                body: "Это уже легенда. Иди к ней."
            ))
        }
        return pool.randomElement() ?? pool[0]
    }

    /// "12 июня" -- the ru locale yields the genitive month with "d MMMM".
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMMM"
        return f
    }()
}
