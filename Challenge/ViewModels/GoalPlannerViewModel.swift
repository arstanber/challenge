import Foundation
import Supabase
import Functions
import PostgREST
import Observation
import os.log

private let logger = Logger(subsystem: "com.challenge", category: "GoalPlannerViewModel")

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
            errorMessage = extractFunctionError(error)
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
            AnalyticsService.shared.track(.goalPlanGenerated, ["activities": response.activities.count])
            step = .plan
        } catch {
            errorMessage = extractFunctionError(error)
            step = .questions
        }
    }

    // MARK: - Create all activities in Supabase

    func createActivities() async {
        guard let plan, let user = authService.currentUser else { return }
        step = .creating
        errorMessage = nil
        createdCount = 0

        let sharedPlanId = UUID()
        let sharedPlanTitle = plan.title

        // 1. Create parent goal activity
        let maxDeadline: Date? = plan.activities.compactMap { a in
            a.deadlineDays.map { Calendar.current.date(byAdding: .day, value: $0, to: Date()) ?? Date() }
        }.max()

        let parentReq = CreateActivityRequest(
            userId: user.id,
            assignedBy: nil,
            title: plan.title,
            description: plan.summary,
            type: .goal,
            condition: nil,
            frequency: .once,
            deadline: maxDeadline,
            reminderTime: nil,
            goalTarget: nil,
            planId: sharedPlanId,
            planTitle: sharedPlanTitle,
            parentId: nil
        )

        guard let parent: Activity = try? await supabase
            .from("activities")
            .insert(parentReq)
            .select()
            .single()
            .execute()
            .value
        else {
            errorMessage = "Failed to create goal"
            step = .questions
            return
        }

        // 2. Create subtasks with parent_id pointing to the parent goal
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
                goalTarget: activity.goalTarget,
                planId: sharedPlanId,
                planTitle: sharedPlanTitle,
                parentId: parent.id
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
                logger.error("Failed to create subtask '\(activity.title)': \(error)")
            }
        }
        step = .done
    }

    // MARK: - Error extraction

    private func extractFunctionError(_ error: Error) -> String {
        // Try to decode {"error": "..."} from the function response body
        if let fnError = error as? FunctionsError,
           case .httpError(_, let data) = fnError,
           let body = try? JSONDecoder().decode([String: String].self, from: data),
           let msg = body["error"] {
            return msg
        }
        return error.localizedDescription
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
