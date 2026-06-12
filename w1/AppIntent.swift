//
//  AppIntent.swift
//  w1
//
//  Created by Арслан Бердонгар on 05.06.2026.
//

import WidgetKit
import AppIntents

/// Interactive check-off for non-photo tasks straight from the home screen.
/// The widget process has no Supabase session, so the intent queues the
/// completion in the App Group; the app replays it on next open.
struct CompleteTaskIntent: AppIntent {
    static var title: LocalizedStringResource { "Complete task" }
    static var description: IntentDescription { "Mark a task as done right from the widget." }

    @Parameter(title: "Task ID")
    var taskId: String

    init() {}

    init(taskId: UUID) {
        self.taskId = taskId.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: taskId) {
            WidgetDataStore.queueCheckin(id)
        }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
