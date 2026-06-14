import Foundation
import Supabase

enum GeminiError: LocalizedError {
    case emptyResponse
    case server(String)

    var errorDescription: String? {
        switch self {
        case .emptyResponse:    return "AI returned no tasks."
        case .server(let msg):  return "AI error: \(msg)"
        }
    }
}

// MARK: - GeminiTask

/// Task extracted from a spoken transcript. Schedule fields are nil until the
/// user completes the optional "when?" voice step in ConfirmTasksView.
struct GeminiTask: Hashable {
    let title: String
    /// SPORT | HEALTH | FOOD | STUDY | WORK | FINANCE | HOME | MENTAL HEALTH | SOCIAL | OTHER
    let category: String
    /// "habit" | "goal" | "task"
    let type: String

    // Filled in by parseSchedule() after the second voice step.
    var scheduleLabel: String? = nil
    var durationLabel: String? = nil
    var scheduleFrequency: String? = nil  // "once" | "daily" | "weekly"
    var reminderHour: Int? = nil
    var reminderMinute: Int? = nil
    var deadlineDays: Int? = nil
}

extension GeminiTask: Decodable {
    enum CodingKeys: String, CodingKey { case title, category, type }
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title    = try c.decode(String.self, forKey: .title)
        category = try c.decode(String.self, forKey: .category)
        type     = try c.decode(String.self, forKey: .type)
    }
}

// MARK: - GeminiService

final class GeminiService {
    static let shared = GeminiService()
    private init() {}

    // MARK: Parse tasks

    private struct ParseTasksRequest: Encodable { let transcript: String }

    private struct ParseTasksResponse: Decodable {
        let tasks: [GeminiTask]?
        let error: String?
    }

    func parseTasks(from transcript: String) async throws -> [GeminiTask] {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let response: ParseTasksResponse = try await supabase.functions
            .invoke("parse-tasks", options: FunctionInvokeOptions(body: ParseTasksRequest(transcript: trimmed)))

        if let error = response.error { throw GeminiError.server(error) }
        return response.tasks ?? []
    }

    // MARK: Parse schedule

    private struct ParseScheduleRequest: Encodable {
        let tasks: [String]
        let transcript: String
    }

    struct ScheduleEntry: Decodable {
        let index: Int
        let scheduleLabel: String
        let durationLabel: String?
        let frequency: String
        let hour: Int?
        let minute: Int?
        let deadlineDays: Int?
    }

    private struct ParseScheduleResponse: Decodable {
        let schedules: [ScheduleEntry]?
        let error: String?
    }

    // MARK: Categorize

    private struct CategorizeRequest: Encodable { let titles: [String] }
    private struct CategorizeResponse: Decodable {
        let categories: [String]?
        let error: String?
    }

    /// Returns one category label per input title (same order). Empty on failure.
    func categorize(titles: [String]) async throws -> [String] {
        guard !titles.isEmpty else { return [] }
        let response: CategorizeResponse = try await supabase.functions
            .invoke("categorize", options: FunctionInvokeOptions(body: CategorizeRequest(titles: titles)))
        if let error = response.error { throw GeminiError.server(error) }
        return response.categories ?? []
    }

    func parseSchedule(tasks: [String], transcript: String) async throws -> [ScheduleEntry] {
        let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let response: ParseScheduleResponse = try await supabase.functions
            .invoke("parse-schedule", options: FunctionInvokeOptions(
                body: ParseScheduleRequest(tasks: tasks, transcript: trimmed)
            ))

        if let error = response.error { throw GeminiError.server(error) }
        return response.schedules ?? []
    }
}
