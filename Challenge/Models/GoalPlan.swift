import Foundation

// MARK: - Phase 1: Questions

struct GoalQuestionsRequest: Encodable {
    let goalDescription: String
    enum CodingKeys: String, CodingKey { case goalDescription = "goal_description" }
}

struct GoalQuestionsResponse: Decodable {
    let questions: [String]
}

// MARK: - Phase 2: Plan

struct GoalPlanRequest: Encodable {
    let goalDescription: String
    let answers: [GoalAnswerPair]
    enum CodingKeys: String, CodingKey {
        case goalDescription = "goal_description"
        case answers
    }
}

struct GoalAnswerPair: Encodable {
    let question: String
    let answer: String
}

struct GoalPlanResponse: Decodable {
    let title: String
    let summary: String
    let activities: [PlannedActivity]

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        title      = try c.decodeIfPresent(String.self,            forKey: .title)      ?? "Your Plan"
        summary    = try c.decodeIfPresent(String.self,            forKey: .summary)    ?? ""
        activities = try c.decodeIfPresent([PlannedActivity].self, forKey: .activities) ?? []
    }

    enum CodingKeys: CodingKey { case title, summary, activities }
}

struct PlannedActivity: Decodable, Identifiable {
    var id = UUID()
    let stepNumber: Int
    let title: String
    let description: String
    let type: ActivityType
    let frequency: ActivityFrequency
    let condition: String?
    let goalTarget: Double?
    let deadlineDays: Int?
    let rationale: String

    enum CodingKeys: String, CodingKey {
        case stepNumber = "step_number"
        case title, description, type, frequency, condition
        case goalTarget = "goal_target"
        case deadlineDays = "deadline_days"
        case rationale
    }

    // Custom decoder: gracefully fall back for unknown enum values
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        stepNumber   = try c.decodeIfPresent(Int.self,    forKey: .stepNumber)  ?? 1
        title        = try c.decode(String.self,          forKey: .title)
        description  = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        let typeRaw  = try c.decodeIfPresent(String.self, forKey: .type) ?? "task"
        type         = ActivityType(rawValue: typeRaw) ?? .task
        let freqRaw  = try c.decodeIfPresent(String.self, forKey: .frequency) ?? "daily"
        frequency    = ActivityFrequency(rawValue: freqRaw) ?? .daily
        condition    = try c.decodeIfPresent(String.self, forKey: .condition)
        goalTarget   = try c.decodeIfPresent(Double.self, forKey: .goalTarget)
        deadlineDays = try c.decodeIfPresent(Int.self,    forKey: .deadlineDays)
        rationale    = try c.decodeIfPresent(String.self, forKey: .rationale) ?? ""
    }
}

// MARK: - Local UI model

struct GoalAnswer: Identifiable {
    let id = UUID()
    let question: String
    var answer: String = ""
}
