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
}

// MARK: - Local UI model

struct GoalAnswer: Identifiable {
    let id = UUID()
    let question: String
    var answer: String = ""
}
