import Foundation
import Supabase
import Functions
import PostgREST
import Observation
import os.log

private let logger = Logger(subsystem: "com.reinspire", category: "GoalPlannerViewModel")

@Observable
@MainActor
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
    /// Optional deadline for the goal, picked by the user before generating the plan.
    var deadline: Date?

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
        let maxStepDeadline: Date? = plan.activities.compactMap { a in
            a.deadlineDays.map { Calendar.current.date(byAdding: .day, value: $0, to: Date()) ?? Date() }
        }.max()

        // The user-picked deadline (if any) is the goal's hard cutoff -- it wins
        // over the AI's step-based estimate.
        let parentDeadline = deadline ?? maxStepDeadline

        let parentReq = CreateActivityRequest(
            userId: user.id,
            assignedBy: nil,
            title: plan.title,
            description: plan.summary,
            type: .goal,
            condition: nil,
            frequency: .once,
            deadline: parentDeadline,
            reminderTime: nil,
            goalTarget: nil,
            completionMode: .check,
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
            var stepDeadline: Date? = activity.deadlineDays.map {
                Calendar.current.date(byAdding: .day, value: $0, to: Date()) ?? Date()
            }
            // Don't let a subtask's estimated deadline fall after the goal's own deadline.
            if let goalDeadline = parentDeadline, let candidate = stepDeadline, candidate > goalDeadline {
                stepDeadline = goalDeadline
            }
            let req = CreateActivityRequest(
                userId: user.id,
                assignedBy: nil,
                title: activity.title,
                description: activity.description,
                type: activity.type,
                condition: activity.condition,
                frequency: activity.frequency,
                deadline: stepDeadline,
                reminderTime: nil,
                goalTarget: activity.goalTarget,
                completionMode: activity.goalTarget == nil ? .check : .counter,
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
        // One combined connector suggestion for the whole AI plan
        // (e.g. a running goal proposes Health/Strava once, not per subtask).
        let createdTopics: [(title: String, description: String, category: String?)] =
            [(plan.title, plan.summary, nil)] + plan.activities.map { ($0.title, $0.description, nil) }
        ConnectorSuggestionEngine.shared.tasksCreated(createdTopics)
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
        deadline = nil
    }
}
