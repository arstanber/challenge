import AppIntents
import Foundation

/// App Intents power the "Команды" (Apple Shortcuts) connector: they make
/// reInspire appear in the Shortcuts app and Siri. They read shared state from
/// the widget app group, so they work without launching the full app.
///
/// `ReInspireAppShortcuts` exposes a set of ready-made templates that show up
/// automatically in the Shortcuts gallery -- the user can run them as-is or drop
/// them into their own automations.

// MARK: - Task entity (powers the "отметить задачу" picker)

/// A today-task surfaced to Shortcuts so the user can pick one in the
/// "Отметить задачу" template. Backed by the shared widget snapshot.
@available(iOS 17.0, *)
struct ReInspireTaskEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Задача")
    static var defaultQuery = ReInspireTaskQuery()

    var id: UUID
    var title: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(title)")
    }

    /// Only tasks that can be completed without the camera -- photo tasks need
    /// the full app, so they're filtered out of the picker.
    @MainActor
    static func openCheckableTasks() -> [ReInspireTaskEntity] {
        (WidgetDataStore.load()?.tasks ?? [])
            .filter {
                !$0.isDone
                    && !PhotoVerificationPolicy.requiresPhotoForEveryTask
                    && !($0.requiresPhoto ?? false)
            }
            .map { ReInspireTaskEntity(id: $0.id, title: $0.title) }
    }
}

@available(iOS 17.0, *)
struct ReInspireTaskQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [UUID]) async throws -> [ReInspireTaskEntity] {
        ReInspireTaskEntity.openCheckableTasks().filter { identifiers.contains($0.id) }
    }

    @MainActor
    func suggestedEntities() async throws -> [ReInspireTaskEntity] {
        ReInspireTaskEntity.openCheckableTasks()
    }
}

// MARK: - Open

@available(iOS 17.0, *)
struct OpenReInspireIntent: AppIntent {
    static var title: LocalizedStringResource = "Открыть reInspire"
    static var description = IntentDescription("Открывает приложение reInspire.")
    static var openAppWhenRun = true

    func perform() async throws -> some IntentResult { .result() }
}

// MARK: - Read-only progress templates

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
struct BestStreakIntent: AppIntent {
    static var title: LocalizedStringResource = "Лучшая серия"
    static var description = IntentDescription("Самая длинная серия дней в reInspire.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        let best = WidgetDataStore.load()?.streakBest ?? 0
        return .result(value: best, dialog: IntentDialog(stringLiteral: "Твой рекорд: \(best) дн."))
    }
}

@available(iOS 17.0, *)
struct RemainingTasksIntent: AppIntent {
    static var title: LocalizedStringResource = "Что осталось сегодня"
    static var description = IntentDescription("Список невыполненных задач на сегодня.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<[String]> {
        let remaining = (WidgetDataStore.load()?.tasks ?? []).filter { !$0.isDone }
        let titles = remaining.map(\.title)
        let dialog: String
        if titles.isEmpty {
            dialog = "На сегодня всё выполнено. Так держать!"
        } else {
            dialog = "Осталось задач: \(titles.count). " + titles.joined(separator: ", ")
        }
        return .result(value: titles, dialog: IntentDialog(stringLiteral: dialog))
    }
}

@available(iOS 17.0, *)
struct WeeklyProgressIntent: AppIntent {
    static var title: LocalizedStringResource = "Прогресс за неделю"
    static var description = IntentDescription("Процент выполнения за последнюю завершённую неделю.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<Int> {
        // weekRates: index 0 = oldest, last entry = current week in progress.
        let rates = WidgetDataStore.load()?.weekRates ?? []
        let rate = rates.last ?? 0
        let percent = Int((rate * 100).rounded())
        return .result(value: percent, dialog: IntentDialog(stringLiteral: "Прогресс за неделю: \(percent)%."))
    }
}

// MARK: - Action template: check off a task

@available(iOS 17.0, *)
struct CompleteTaskShortcutIntent: AppIntent {
    static var title: LocalizedStringResource = "Отметить задачу"
    static var description = IntentDescription(
        "Отмечает выбранную задачу выполненной. Задачи с фото-проверкой нужно подтверждать в приложении."
    )

    @Parameter(title: "Задача")
    var task: ReInspireTaskEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Отметить \(\.$task) выполненной")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        WidgetDataStore.queueCheckin(task.id)
        return .result(dialog: IntentDialog(stringLiteral: "Готово: «\(task.title)» отмечена выполненной."))
    }
}

// MARK: - Shortcuts gallery templates

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
            intent: RemainingTasksIntent(),
            phrases: ["Что осталось в \(.applicationName)", "Какие задачи в \(.applicationName)"],
            shortTitle: "Что осталось сегодня",
            systemImageName: "checklist"
        )
        AppShortcut(
            intent: CompleteTaskShortcutIntent(),
            phrases: ["Отметь задачу в \(.applicationName)", "Выполнил задачу в \(.applicationName)"],
            shortTitle: "Отметить задачу",
            systemImageName: "checkmark.circle.fill"
        )
        AppShortcut(
            intent: CurrentStreakIntent(),
            phrases: ["Моя серия в \(.applicationName)", "Какая у меня серия в \(.applicationName)"],
            shortTitle: "Моя серия",
            systemImageName: "flame.fill"
        )
        AppShortcut(
            intent: BestStreakIntent(),
            phrases: ["Мой рекорд в \(.applicationName)", "Лучшая серия в \(.applicationName)"],
            shortTitle: "Лучшая серия",
            systemImageName: "trophy.fill"
        )
        AppShortcut(
            intent: WeeklyProgressIntent(),
            phrases: ["Прогресс за неделю в \(.applicationName)", "Как прошла неделя в \(.applicationName)"],
            shortTitle: "Прогресс за неделю",
            systemImageName: "calendar"
        )
    }
}
