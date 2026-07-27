import Foundation
import UIKit
import Supabase
import PostgREST
import Storage
import Observation

@MainActor
@Observable
final class ActivityDetailViewModel {
    var activity: Activity
    var reports: [Report] = []
    private(set) var todayProgress: Double
    var isLoading = false
    var isSubmittingReport = false
    var errorMessage: String?

    /// Drives the staged progress UI while a photo report is in flight.
    enum SubmissionStage { case idle, uploading, verifying }
    var submissionStage: SubmissionStage = .idle

    /// Set after photo submission — SubmitReportView uses this to show the verdict screen
    var lastAIResult: AIVerificationResult?
    var lastAIExplanation: String?

    /// True when the server rejected verification with 429 (monthly AI quota spent) —
    /// the view offers Premium instead of failing silently
    var aiLimitReached = false

    /// Called after any successful counted submission so global streak refreshes
    var onReportSubmitted: (() -> Void)?

    private let aiService = AIVerificationService.shared

    init(activity: Activity) {
        self.activity = activity
        self.todayProgress = activity.frequency == .once ? activity.goalProgress : 0
    }

    // MARK: - Load

    func loadReports() async {
        isLoading = true
        do {
            reports = try await supabase
                .from("reports")
                .select()
                .eq("activity_id", value: activity.id.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
            await refreshMeasurableProgress()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Activation funnel

    /// The first photo verdict is the app's aha moment. Fired once per
    /// install; hours_since_signup feeds the 24-hour activation metric.
    /// The same flag hides the FirstWinCard on Home.
    private func trackFirstReportIfNeeded(result: AIVerificationResult) {
        let key = "hasSubmittedFirstReport"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        var props: [String: Any] = ["result": result.rawValue]
        if let signupDate = AuthService.shared.currentUser?.createdAt {
            props["hours_since_signup"] = Int(Date().timeIntervalSince(signupDate) / 3600)
        }
        AnalyticsService.shared.track(.firstReportSubmitted, props)
    }

    // MARK: - Photo report (challenge / assignment)

    func submitPhotoReport(image: UIImage, comment: String, isExcuse: Bool = false) async {
        isSubmittingReport = true
        submissionStage = .uploading
        errorMessage = nil
        lastAIResult = nil
        lastAIExplanation = nil
        defer { isSubmittingReport = false; submissionStage = .idle }

        // Offline: stash the photo and accept the task now -- it uploads and gets
        // AI-verified automatically on the next reconnect.
        if !NetworkMonitor.shared.isOnline {
            PendingPhotoStore.shared.enqueue(image: image, activity: activity, isExcuse: isExcuse, comment: comment)
            TaskEngine.shared.markDoneLocally(activity.id)
            if activity.frequency == .once { await markCompleted() }
            lastAIResult = .notApplicable
            lastAIExplanation = AppLanguage.current == "ru"
                ? "Нет интернета -- проверим фото, как только появится сеть."
                : "No internet -- we'll check the photo as soon as you're back online."
            LiveActivityService.shared.resolveVerifying(taskId: activity.id, approved: true)
            onReportSubmitted?()
            await TaskEngine.shared.noteReportChanged(activityId: activity.id)
            return
        }

        do {
            // 1. Upload photo (downscaled to ~1280px -- huge upload/latency win)
            guard let jpeg = image.compressedForUpload() else { return }
            let path = "\(activity.id.uuidString)/\(UUID().uuidString).jpg"
            try await supabase.storage
                .from(Constants.Storage.reportsBucket)
                .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg"))
            let photoURL = try supabase.storage
                .from(Constants.Storage.reportsBucket)
                .getPublicURL(path: path)
                .absoluteString

            // 2. Create report record
            let req = CreateReportRequest(
                activityId: activity.id,
                photoURL: photoURL,
                comment: comment.isEmpty ? nil : comment
            )
            let report: Report = try await supabase
                .from("reports")
                .insert(req)
                .select()
                .single()
                .execute()
                .value
            reports.insert(report, at: 0)

            // 3. AI verification — runs for EVERY task now.
            //    Verifies against the photo description (condition) if set, otherwise the title.
            let trimmedCondition = activity.condition?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let condition = trimmedCondition.isEmpty ? activity.title : trimmedCondition

            do {
                submissionStage = .verifying
                LiveActivityService.shared.setVerifying(taskId: activity.id, title: activity.title)
                let aiResponse = try await aiService.verify(
                    reportId:   report.id,
                    activityId: activity.id,
                    condition:  condition,
                    photoURL:   photoURL,
                    isExcuse:   isExcuse
                )

                // Determine result. The verdict row is written server-side by the
                // verify-report edge function -- clients cannot write ai_result
                // (blocked by the protect_ai_verdict DB trigger).
                let resultEnum: AIVerificationResult
                if aiResponse.approved {
                    resultEnum = .approved
                } else if aiResponse.excused {
                    resultEnum = .excused
                } else {
                    resultEnum = .rejected
                }

                if let remaining = aiResponse.remaining {
                    RateLimiterService.shared.syncRemaining(remaining, for: .verifyReport)
                }

                if let idx = reports.firstIndex(where: { $0.id == report.id }) {
                    reports[idx].aiResult      = resultEnum
                    reports[idx].aiExplanation = aiResponse.explanation
                }

                lastAIResult      = resultEnum
                lastAIExplanation = aiResponse.explanation

                trackFirstReportIfNeeded(result: resultEnum)

                switch resultEnum {
                case .approved:
                    AnalyticsService.shared.track(.verificationSucceeded, ["activity_type": activity.type.rawValue])
                case .excused:
                    AnalyticsService.shared.track(.excuseUsed, ["activity_type": activity.type.rawValue])
                default:
                    AnalyticsService.shared.track(.verificationFailed, ["activity_type": activity.type.rawValue])
                }

                switch resultEnum {
                case .approved:
                    if activity.frequency == .once { await markCompleted() }
                    onReportSubmitted?()
                case .excused:
                    // Excuse accepted — activity stays active, streak not counted but not penalised
                    break
                default:
                    // Rejected — nothing
                    break
                }
                // Drive the island spinner -> check. Approved/excused/not_applicable
                // hold or count the day; only an outright rejection is "not done".
                LiveActivityService.shared.resolveVerifying(taskId: activity.id, approved: resultEnum != .rejected)
                await TaskEngine.shared.noteReportChanged(activityId: activity.id)
            } catch {
                if let fnError = error as? FunctionsError,
                   case .httpError(let code, _) = fnError, code == 429 {
                    aiLimitReached = true
                }
                // Verification unavailable (offline / monthly limit reached) — don't hard-block:
                // accept the photo so the user can still complete the task.
                lastAIResult = .notApplicable
                if activity.frequency == .once { await markCompleted() }
                onReportSubmitted?()
                LiveActivityService.shared.resolveVerifying(taskId: activity.id, approved: true)
                await TaskEngine.shared.noteReportChanged(activityId: activity.id)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Task / Habit report

    func submitTaskReport() async {
        isSubmittingReport = true
        errorMessage = nil
        defer { isSubmittingReport = false }
        // Offline: tick now and let TaskEngine replay the check-in on reconnect.
        if !NetworkMonitor.shared.isOnline {
            await TaskEngine.shared.markDone(activity)
            if activity.frequency == .once { await markCompleted() }
            onReportSubmitted?()
            return
        }
        do {
            let req = CreateReportRequest(activityId: activity.id)
            let report: Report = try await supabase
                .from("reports")
                .insert(req)
                .select()
                .single()
                .execute()
                .value
            reports.insert(report, at: 0)
            if activity.frequency == .once { await markCompleted() }
            onReportSubmitted?()
            await TaskEngine.shared.noteReportChanged(activityId: activity.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Goal progress

    func submitGoalProgress(value: Double, image: UIImage?) async {
        isSubmittingReport = true
        errorMessage = nil
        defer { isSubmittingReport = false }
        do {
            let update = try await ActivityProgressService.record(
                activityId: activity.id,
                value: value
            )
            activity.goalProgress = update.displayProgress
            todayProgress = update.dailyProgress
            if activity.frequency == .once, update.targetReached {
                activity.status = .completed
            }
            if update.reportCreated {
                await reloadReportsOnly()
                await TaskEngine.shared.noteReportChanged(activityId: activity.id)
            }
            onReportSubmitted?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Auto-complete a connector-tracked goal once today's live value reaches
    /// the target (e.g. 10000 steps from Health, 1 game from Chess.com). Inserts
    /// a plain check-in so it counts toward the day + streak, and finishes a
    /// one-off goal. No-op if already done today or the target isn't met.
    func autoCompleteIfGoalMet(connectorValue: Double) async {
        guard let target = activity.goalTarget, target > 0,
              connectorValue >= target, !isDoneToday else { return }
        do {
            let current = activity.frequency == .once ? activity.goalProgress : todayProgress
            let increment = max(0, connectorValue - current)
            guard increment > 0 else { return }
            let update = try await ActivityProgressService.record(
                activityId: activity.id,
                value: increment
            )
            activity.goalProgress = update.displayProgress
            todayProgress = update.dailyProgress
            if update.reportCreated {
                await reloadReportsOnly()
                await TaskEngine.shared.noteReportChanged(activityId: activity.id)
            }
            onReportSubmitted?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Calendar / streak helpers (habit detail)

    private let cal = Calendar.current

    /// Distinct days (start-of-day) on which this habit was completed.
    /// Rejected photos do not paint the calendar.
    var completedDays: Set<Date> {
        Set(reports.filter { $0.aiResult != .rejected }.map { cal.startOfDay(for: $0.createdAt) })
    }

    var isDoneToday: Bool {
        TaskEngine.shared.isDoneToday(activity.id)
            || completedDays.contains(cal.startOfDay(for: Date()))
    }

    var totalDaysDone: Int { completedDays.count }

    /// Current streak: server-maintained column (kept fresh by the reports
    /// trigger + refresh_my_streaks), local recomputation as offline seed.
    var currentStreak: Int {
        if let s = TaskEngine.shared.activityStreaks[activity.id] { return s.current }
        return max(activity.streakCurrent, localCurrentStreak)
    }

    /// Best streak: server-maintained column, local recomputation as offline seed.
    var bestStreak: Int {
        if let s = TaskEngine.shared.activityStreaks[activity.id] { return s.best }
        return max(activity.streakBest, localBestStreak)
    }

    // Offline fallback, server is canonical (schedule-aware off-days are only
    // handled server-side; this is a plain consecutive-day approximation).
    private var localCurrentStreak: Int {
        let days = completedDays
        guard !days.isEmpty else { return 0 }
        let today = cal.startOfDay(for: Date())
        let yesterday = cal.date(byAdding: .day, value: -1, to: today)!
        guard days.contains(today) || days.contains(yesterday) else { return 0 }
        var streak = 0
        var cursor = days.contains(today) ? today : yesterday
        while days.contains(cursor) {
            streak += 1
            cursor = cal.date(byAdding: .day, value: -1, to: cursor)!
        }
        return streak
    }

    private var localBestStreak: Int {
        let sorted = completedDays.sorted()
        guard !sorted.isEmpty else { return 0 }
        var best = 1, temp = 1
        for i in 1..<sorted.count {
            let diff = cal.dateComponents([.day], from: sorted[i-1], to: sorted[i]).day ?? 0
            if diff == 1 { temp += 1; best = max(best, temp) } else { temp = 1 }
        }
        return best
    }

    /// Toggle today's completion: check off if not done, undo if already done.
    func toggleToday() async {
        if isDoneToday {
            await undoToday()
        } else {
            await submitTaskReport()
        }
    }

    /// Remove today's report(s) for this activity (undo).
    func undoToday() async {
        if activity.effectiveCompletionMode.needsTarget {
            do {
                try await ActivityProgressService.resetToday(activityId: activity.id)
                activity.goalProgress = 0
                todayProgress = 0
                await reloadReportsOnly()
                await TaskEngine.shared.undoToday(activityId: activity.id)
                onReportSubmitted?()
            } catch {
                errorMessage = error.localizedDescription
            }
            return
        }

        let start = cal.startOfDay(for: Date())
        let iso = ISO8601DateFormatter()
        do {
            try await supabase
                .from("reports")
                .delete()
                .eq("activity_id", value: activity.id.uuidString)
                .gte("created_at", value: iso.string(from: start))
                .execute()
            reports.removeAll { cal.isDate($0.createdAt, inSameDayAs: start) }
            await TaskEngine.shared.undoToday(activityId: activity.id)
            onReportSubmitted?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Subtask creation (GoalSplitSheet #12)

    func createSubtasks(_ subtasks: [SplitTask]) async {
        guard let user = AuthService.shared.currentUser else { return }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        for sub in subtasks {
            let deadline: Date? = sub.estimatedDays.flatMap {
                cal.date(byAdding: .day, value: $0, to: today)
            }
            let req = CreateActivityRequest(
                userId: user.id,
                assignedBy: nil,
                title: sub.title,
                description: "",
                type: .task,
                condition: nil,
                frequency: .once,
                deadline: deadline,
                reminderTime: nil,
                goalTarget: nil,
                planId: nil,
                planTitle: nil,
                workspaceId: activity.workspaceId,
                parentId: activity.id
            )
            do {
                try await supabase
                    .from("activities")
                    .insert(req)
                    .execute()
            } catch {
                errorMessage = error.localizedDescription
                return
            }
        }
        // The AI split inherits the goal's topic: suggest connectors once per batch.
        let createdTopics: [(title: String, description: String, category: String?)] =
            subtasks.map { ($0.title, "", nil) }
        ConnectorSuggestionEngine.shared.tasksCreated(createdTopics)
    }

    // MARK: - Helpers

    private func refreshMeasurableProgress() async {
        guard activity.effectiveCompletionMode.needsTarget else { return }
        do {
            let snapshots = try await ActivityProgressService.loadToday()
            let daily = snapshots.first(where: { $0.activityId == activity.id })?.dailyProgress ?? 0
            todayProgress = daily
            if activity.frequency != .once {
                activity.goalProgress = daily
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func reloadReportsOnly() async {
        do {
            reports = try await supabase
                .from("reports")
                .select()
                .eq("activity_id", value: activity.id.uuidString)
                .order("created_at", ascending: false)
                .execute()
                .value
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func markCompleted() async {
        activity.status = .completed
        await SyncService.shared.perform(
            .updateActivity(id: activity.id, fields: ["status": .string("completed")])
        )
    }
}
