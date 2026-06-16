import AppIntents
import Foundation

/// App Intents power the "Команды" (Apple Shortcuts) connector: they make
/// reInspire appear in the Shortcuts app and Siri. They read shared state from
/// the widget app group, so they work without launching the full app.

@available(iOS 17.0, *)
struct OpenReInspireIntent: AppIntent {
    static var title: LocalizedStringResource = "Открыть reInspire"
    static var description = IntentDescription("Открывает приложение reInspire.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult { .result() }
}

@available(iOS 17.0, *)
struct TodayProgressIntent: AppIntent {
    static var title: LocalizedStringResource = "Прогресс за сегодня"
    static var description = IntentDescription("Сколько задач выполнено сегодня в reInspire.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        let snap = WidgetDataStore.load()
        let done = snap?.todayDone ?? 0
        let goal = snap?.dailyGoal ?? 0
        let streak = snap?.streakCurrent ?? 0
        let dialog: String
        if goal > 0 {
            dialog = "Сегодня выполнено \(done) из \(goal). Серия: \(streak) дн."
        } else {
            dialog = "Сегодня выполнено задач: \(done). Серия: \(streak) дн."
        }
        return .result(value: done, dialog: IntentDialog(stringLiteral: dialog))
    }
}

@available(iOS 17.0, *)
struct CurrentStreakIntent: AppIntent {
    static var title: LocalizedStringResource = "Моя серия"
    static var description = IntentDescription("Текущая серия дней в reInspire.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        let streak = WidgetDataStore.load()?.streakCurrent ?? 0
        return .result(value: streak, dialog: IntentDialog(stringLiteral: "Твоя серия: \(streak) дн."))
    }
}

@available(iOS 17.0, *)
struct ReInspireAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenReInspireIntent(),
            phrases: ["Открой \(.applicationName)", "Запусти \(.applicationName)"],
            shortTitle: "Открыть",
            systemImageName: "app.fill"
        )
        AppShortcut(
            intent: TodayProgressIntent(),
            phrases: ["Мой прогресс в \(.applicationName)", "Сколько задач в \(.applicationName)"],
            shortTitle: "Прогресс за сегодня",
            systemImageName: "chart.bar.fill"
        )
        AppShortcut(
            intent: CurrentStreakIntent(),
            phrases: ["Моя серия в \(.applicationName)", "Какая у меня серия в \(.applicationName)"],
            shortTitle: "Моя серия",
            systemImageName: "flame.fill"
        )
    }
}
