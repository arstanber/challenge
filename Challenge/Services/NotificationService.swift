import Foundation
import UIKit
import UserNotifications
import Supabase
import PostgREST
import Observation
import os.log

private let notifLogger = Logger(subsystem: "com.challenge", category: "NotificationService")

@Observable
final class NotificationService: NSObject {
    static let shared = NotificationService()

    var permissionGranted = false

    private override init() {
        super.init()
        checkPermission()
    }

    func requestPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .badge, .sound])
            permissionGranted = granted
            if granted { await registerForRemoteNotifications() }
        } catch {
            notifLogger.error("Notification permission error: \(error)")
        }
    }

    private func checkPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.permissionGranted = settings.authorizationStatus == .authorized
            }
        }
    }

    @MainActor
    private func registerForRemoteNotifications() async {
        #if !targetEnvironment(simulator)
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }

    func scheduleLocalReminder(for activity: Activity) {
        guard let reminderTime = activity.reminderTime else { return }
        // Replace any previously scheduled variant (frequency/days may have changed).
        cancelReminder(for: activity.id)

        let content = UNMutableNotificationContent()
        content.title = NSLocalizedString("Don't forget!", comment: "")
        content.body = String(format: NSLocalizedString("Submit your report for %@", comment: ""), activity.title)
        content.sound = .default
        content.userInfo = ["activity_id": activity.id.uuidString]

        var components = Calendar.current.dateComponents([.hour, .minute], from: reminderTime)
        components.second = 0

        let center = UNUserNotificationCenter.current()
        if activity.frequency == .weekly, let days = activity.scheduleDays, !days.isEmpty {
            // One repeating request per scheduled weekday.
            // schedule_days is ISO (Mon=1..Sun=7); DateComponents.weekday is Sun=1..Sat=7.
            for iso in days {
                var comps = components
                comps.weekday = iso == 7 ? 1 : iso + 1
                let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
                let request = UNNotificationRequest(identifier: "reminder-\(activity.id)-\(iso)", content: content, trigger: trigger)
                center.add(request)
            }
        } else {
            let repeats = activity.frequency == .daily || activity.frequency == .weekly
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: repeats)
            let request = UNNotificationRequest(identifier: "reminder-\(activity.id)", content: content, trigger: trigger)
            center.add(request)
        }
    }

    func cancelReminder(for activityId: UUID) {
        // Legacy un-suffixed identifier plus the 7 per-weekday variants.
        let ids = ["reminder-\(activityId)"] + (1...7).map { "reminder-\(activityId)-\($0)" }
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ids)
    }

    // MARK: - Bulk reminder sync

    /// Re-schedule per-task reminders for every active activity that has a reminder time.
    func syncReminders(for activities: [Activity]) {
        for activity in activities where activity.status == .active && activity.reminderTime != nil {
            scheduleLocalReminder(for: activity)
        }
    }

    // MARK: - Streak evening nudge

    /// One-shot reminder today at `hour` if the user hasn't kept their streak yet.
    /// Re-scheduled on every app open, so it only fires on days that are still incomplete.
    func scheduleStreakNudge(hour: Int = 20) {
        let id = "streak-nudge"
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])

        let now = Date()
        let cal = Calendar.current
        guard let fireDate = cal.date(bySettingHour: hour, minute: 0, second: 0, of: now),
              fireDate > now else { return }

        let content = UNMutableNotificationContent()
        content.title = "Don't break your streak 🔥"
        content.body = "You still have tasks for today. Finish them before midnight!"
        content.sound = .default

        let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    func cancelStreakNudge() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["streak-nudge"])
    }

    // MARK: - Weekly review

    /// Repeating weekly summary every Sunday at `hour`.
    func scheduleWeeklyReview(hour: Int = 18) {
        let id = "weekly-review"
        let center = UNUserNotificationCenter.current()

        let content = UNMutableNotificationContent()
        content.title = "Your week in review 📊"
        content.body = "See how many tasks you crushed this week and plan the next one."
        content.sound = .default

        var comps = DateComponents()
        comps.weekday = 1 // Sunday
        comps.hour = hour
        comps.minute = 0
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    // MARK: - Daily motivation plan (minimum 15 pushes per day)

    private static let basePlanCount = 15
    private static let maxPlanExtras = 15

    /// Schedules the daily motivation plan: `basePlanCount` pushes spread across
    /// 08:00-22:40 as daily-repeating triggers (so the minimum holds even on days
    /// the app is never opened), plus 2 extra task-flavored pushes per active task
    /// beyond the third. Texts reshuffle every day via a date-seeded RNG, so
    /// re-scheduling on each app open is idempotent within a day.
    func scheduleDailyMotivationPlan(for activities: [Activity]) {
        let center = UNUserNotificationCenter.current()
        let slotIds = (0..<Self.basePlanCount).map { "plan-slot-\($0)" }
        let extraIds = (0..<Self.maxPlanExtras).map { "plan-extra-\($0)" }
        center.removePendingNotificationRequests(withIdentifiers: slotIds + extraIds)

        let active = activities.filter { $0.status == .active }
        let cal = Calendar.current
        let now = Date()
        let dayComps = cal.dateComponents([.year, .dayOfYear], from: now)
        var rng = SeededGenerator(seed: UInt64((dayComps.year ?? 0) * 1000 + (dayComps.dayOfYear ?? 0)))

        var morning = MotivationTexts.morning.shuffled(using: &rng)
        var day = MotivationTexts.day.shuffled(using: &rng)
        var evening = MotivationTexts.evening.shuffled(using: &rng)

        // When a streak is worth protecting, a couple of evening slots talk about it.
        let bestStreak = active.map(\.streakCurrent).max() ?? 0
        if bestStreak >= 3 {
            let streakTexts = MotivationTexts.streak.shuffled(using: &rng).prefix(2).map {
                (String(format: $0.0, bestStreak), String(format: $0.1, bestStreak))
            }
            evening.insert(contentsOf: streakTexts, at: 0)
        }

        let startMin = 8 * 60
        let endMin = 22 * 60 + 40
        let step = (endMin - startMin) / (Self.basePlanCount - 1)

        func pickText(forHour hour: Int) -> (title: String, body: String) {
            switch hour {
            case ..<12:
                if !morning.isEmpty { return morning.removeFirst() }
            case ..<17:
                if !day.isEmpty { return day.removeFirst() }
            default:
                if !evening.isEmpty { return evening.removeFirst() }
            }
            return ("Таски ждут 🎯", "Загляни в список: один отчёт, и день уже не зря.")
        }

        // Base slots: repeat daily, guaranteed minimum.
        for i in 0..<Self.basePlanCount {
            let jitter = Int(rng.next() % 11) - 5
            let minuteOfDay = min(max(startMin, startMin + i * step + jitter), endMin)
            let text = pickText(forHour: minuteOfDay / 60)

            let content = UNMutableNotificationContent()
            content.title = text.title
            content.body = text.body
            content.sound = .default

            var comps = DateComponents()
            comps.hour = minuteOfDay / 60
            comps.minute = minuteOfDay % 60
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            center.add(UNNotificationRequest(identifier: "plan-slot-\(i)", content: content, trigger: trigger))
        }

        // Extras: 2 per active task beyond the third, interleaved between base
        // slots, scheduled for the next occurrence of their time (today or
        // tomorrow). Capped so that together with per-task reminders we stay
        // under the iOS limit of 64 pending requests.
        let extraCount = min(max(0, active.count - 3) * 2, Self.maxPlanExtras)
        guard extraCount > 0, !active.isEmpty else { return }

        for j in 0..<extraCount {
            let minuteOfDay = startMin + (step / 2 + j * step) % (endMin - startMin)
            let task = active[Int(rng.next() % UInt64(active.count))]
            let template = MotivationTexts.taskTemplates[Int(rng.next() % UInt64(MotivationTexts.taskTemplates.count))]

            let content = UNMutableNotificationContent()
            content.title = String(format: template.0, task.title)
            content.body = String(format: template.1, task.title)
            content.sound = .default
            content.userInfo = ["activity_id": task.id.uuidString]

            guard var fireDate = cal.date(bySettingHour: minuteOfDay / 60, minute: minuteOfDay % 60, second: 0, of: now) else { continue }
            if fireDate <= now {
                fireDate = cal.date(byAdding: .day, value: 1, to: fireDate) ?? fireDate
            }
            let comps = cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            center.add(UNNotificationRequest(identifier: "plan-extra-\(j)", content: content, trigger: trigger))
        }
    }

    // MARK: - Send remote push via edge function

    /// Sends a push notification to any user by their Supabase user_id.
    /// Requires APNS_* secrets configured in Supabase → Edge Functions → Secrets.
    func sendPush(toUserId userId: UUID, title: String, body: String, data: [String: String]? = nil) async {
        struct PushRequest: Encodable {
            let user_id: String
            let title: String
            let body: String
            let data: [String: String]?
        }
        let payload = PushRequest(
            user_id: userId.uuidString,
            title: title,
            body: body,
            data: data
        )
        struct PushResult: Decodable { let ok: Bool? }
        do {
            let _: PushResult = try await supabase.functions
                .invoke("send-push", options: FunctionInvokeOptions(body: payload))
        } catch {
            notifLogger.error("sendPush failed: \(error)")
        }
    }

    func saveAPNSToken(_ token: Data, userId: UUID) async {
        let tokenString = token.map { String(format: "%02x", $0) }.joined()
        do {
            try await supabase
                .from("push_tokens")
                .upsert(["user_id": userId.uuidString, "apns_token": tokenString], onConflict: "user_id")
                .execute()
        } catch {
            notifLogger.error("Failed to save APNs token: \(error)")
        }
    }
}

// MARK: - Motivation plan helpers

/// SplitMix64. Deterministic per-day seed keeps the plan stable within a day
/// (idempotent re-scheduling) while reshuffling texts every new day.
private struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed == 0 ? 0x9E3779B97F4A7C15 : seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

private enum MotivationTexts {
    /// (title, body) pairs for the 08:00-11:59 slots.
    static let morning: [(String, String)] = [
        ("Доброе утро, чемпион ☀️", "Лучшее время закрыть первый таск -- пока кофе ещё горячий."),
        ("Утро задаёт тон 🎯", "Один выполненный таск до обеда стоит трёх вечером. Проверено."),
        ("Пока все спят 😴", "Ты уже можешь быть на шаг впереди. Открой список и выбери жертву."),
        ("Завтрак для силы воли 🥞", "Дисциплина тоже хочет есть. Покорми её одним выполненным заданием."),
        ("Будильник для целей ⏰", "Цели сами не просыпаются. Разбуди их фотоотчётом."),
        ("Новый день, чистый лист 📄", "Вчера не считается. Сегодня можно сделать идеальный день."),
        ("Маленький шаг сейчас 👣", "Через десять минут ты скажешь себе утреннему спасибо."),
        ("Кто рано встаёт 🐓", "...тот закрывает таски до того, как день пойдёт кувырком."),
        ("Разминка для воли 💪", "Начни с самого лёгкого таска. Разгон важнее скорости."),
        ("План на день готов? 📋", "Открой список и реши, что закроешь первым. Остальное приложится."),
        ("Солнце уже на работе 🌞", "И оно не ждёт мотивации. Бери пример."),
        ("Это не случайный пуш 😏", "Это знак. Вселенная намекает: пора делать."),
    ]

    /// (title, body) pairs for the 12:00-16:59 slots.
    static let day: [(String, String)] = [
        ("Полдень. Чек-поинт 🕛", "Сколько тасков уже закрыто? Если ноль -- самое время это исправить."),
        ("Обеденный лайфхак 🍽", "Сделай таск до еды, и десерт будет заслуженным."),
        ("Середина дня, середина пути 🏃", "Уже не утро, ещё не вечер. Идеальный момент для рывка."),
        ("Прокрастинация звонила 📞", "Сказала, что подождёт. А вот таски ждать не будут."),
        ("Маленькая победа сейчас 🏆", "Закрой один таск, и день уже прожит не зря."),
        ("Эй, ты как? 👋", "Таски скучают. Загляни к ним на пару минут."),
        ("Фокус-проверка 🔍", "То, что ты делаешь сейчас, приближает к цели? Если нет, ты знаешь, что делать."),
        ("Кофе-брейк с пользой ☕️", "Пять минут на отчёт, и совесть чиста до самого вечера."),
        ("Дневной дозор 🛡", "Стою на страже твоих целей. Докладывай обстановку фотоотчётом."),
        ("Не откладывай на вечер 🌗", "Вечером появятся \"обстоятельства\". Сделай сейчас."),
        ("Псст, есть минутка? ⏳", "Одного закрытого таска хватит, чтобы день засчитался."),
        ("Ты ближе, чем думаешь 📍", "Каждый отчёт -- плюс один шаг. Сделай его прямо сейчас."),
    ]

    /// (title, body) pairs for the 17:00-23:00 slots.
    static let evening: [(String, String)] = [
        ("Финишная прямая 🏁", "До полуночи ещё есть время. Закрой хвосты и спи спокойно."),
        ("Вечерний аудит 🧾", "Пробегись по списку: что из сегодняшнего ещё реально успеть?"),
        ("Огню нужны дрова 🔥", "Серия не любит, когда про неё забывают. Подкинь дров -- закрой таск."),
        ("Завтрашний ты скажет спасибо 🙏", "Сделай сейчас то, что не хочется, и завтра будет легче."),
        ("Ночь близко 🌙", "А незакрытые таски сами себя не закроют. Последний рывок!"),
        ("Идеальный день рядом ✨", "Пара отчётов отделяет тебя от чистого дня. Дожми."),
        ("Дисциплина против дивана 🛋", "Сегодня кто кого? Покажи дивану, кто здесь главный."),
        ("Чек перед сном 🌜", "Всё закрыто? Если нет -- ещё не поздно. Если да -- ты легенда."),
        ("Полночь не дремлет 🕛", "В 00:00 день закроется навсегда. Успей записать себе победу."),
        ("Последний звонок 🔔", "День закрывается через несколько часов. Кто не успел, тот завтра грустит."),
        ("Вечер -- время сильных 💪", "Слабые уже отдыхают. Ты ещё можешь сделать этот день."),
        ("Не оставляй на завтра 📦", "Завтра будут свои таски. Сегодняшние можно закрыть только сегодня."),
    ]

    /// Templates with %@ for the task title; used for the extra per-task pushes.
    static let taskTemplates: [(String, String)] = [
        ("«%@» ждёт 👀", "Этот таск смотрит на тебя весь день. Не выдерживай паузу, закрой его."),
        ("Как там «%@»? 🤨", "Просто напоминаю: он всё ещё в списке. Сам себя он не сделает."),
        ("«%@»: миссия выполнима 🕶", "Десять минут фокуса, фото, отчёт. Готово."),
        ("Свидание с «%@» 📅", "Вы договаривались на сегодня. Не подводи."),
        ("«%@» передаёт привет 💌", "И спрашивает, когда ты уже придёшь его делать."),
        ("Босс-файт: «%@» ⚔️", "Победишь -- получишь плюс к серии и чистую совесть."),
    ]

    /// Templates with %d for the current streak length.
    static let streak: [(String, String)] = [
        ("🔥 Серия: %d дн.", "Такую красоту жалко терять. Один отчёт, и она живёт дальше."),
        ("%d дней без пропусков 💎", "Ты в ударе. Не дай сегодняшнему дню всё испортить."),
        ("Серия %d дн. под угрозой ⚠️", "Полночь всё спишет. Закрой таск, пока огонь горит."),
    ]
}
