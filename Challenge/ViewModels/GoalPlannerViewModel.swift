import Foundation
import Supabase
import PostgREST
import Observation

@Observable
final class GoalPlannerViewModel {

    // MARK: - Step

    enum Step: Equatable {
        case describe
        case loadingQuestions
        case questions
        case generatingPlan
        case plan
        case creating
        case done
    }

    // MARK: - State

    var step: Step = .describe
    var goalDescription = ""
    var answers: [GoalAnswer] = []
    var plan: GoalPlanResponse?
    var errorMessage: String?
    var createdCount = 0

    private let authService = AuthService.shared

    // MARK: - Computed

    var canProceedFromDescribe: Bool {
        goalDescription.trimmingCharacters(in: .whitespaces).count >= 10
    }

    var canProceedFromQuestions: Bool {
        answers.allSatisfy { !$0.answer.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    // MARK: - Phase 1: Get clarifying questions

    func loadQuestions() async {
        step = .loadingQuestions
        errorMessage = nil
        do {
            let req = GoalQuestionsRequest(goalDescription: goalDescription.trimmingCharacters(in: .whitespaces))
            let response: GoalQuestionsResponse = try await supabase.functions
                .invoke("plan-goal", options: FunctionInvokeOptions(body: req))
            answers = response.questions.map { GoalAnswer(question: $0) }
            step = .questions
        } catch {
            errorMessage = error.localizedDescription
            step = .describe
        }
    }

    // MARK: - Phase 2: Generate plan

    func generatePlan() async {
        step = .generatingPlan
        errorMessage = nil
        do {
            let pairs = answers.map { GoalAnswerPair(question: $0.question, answer: $0.answer.trimmingCharacters(in: .whitespaces)) }
            let req = GoalPlanRequest(goalDescription: goalDescription.trimmingCharacters(in: .whitespaces), answers: pairs)
            let response: GoalPlanResponse = try await supabase.functions
                .invoke("plan-goal", options: FunctionInvokeOptions(body: req))
            plan = response
            step = .plan
        } catch {
            errorMessage = error.localizedDescription
            step = .questions
        }
    }

    // MARK: - Create all activities in Supabase

    func createActivities() async {
        guard let plan, let user = authService.currentUser else { return }
        step = .creating
        errorMessage = nil
        createdCount = 0

        for activity in plan.activities {
            let deadline: Date? = activity.deadlineDays.map {
                Calendar.current.date(byAdding: .day, value: $0, to: Date()) ?? Date()
            }
            let req = CreateActivityRequest(
                userId: user.id,
                assignedBy: nil,
                title: activity.title,
                description: activity.description,
                type: activity.type,
                condition: activity.condition,
                frequency: activity.frequency,
                deadline: deadline,
                reminderTime: nil,
                goalTarget: activity.goalTarget
            )
            do {
                let _: Activity = try await supabase
                    .from("activities")
                    .insert(req)
                    .select()
                    .single()
                    .execute()
                    .value
                createdCount += 1
            } catch {
                // Log but continue creating the rest
                print("Failed to create activity '\(activity.title)': \(error)")
            }
        }
        step = .done
    }

    // MARK: - Reset

    func reset() {
        step = .describe
        goalDescription = ""
        answers = []
        plan = nil
        errorMessage = nil
        createdCount = 0
    }
}
