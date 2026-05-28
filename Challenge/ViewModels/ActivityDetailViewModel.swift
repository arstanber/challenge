import Foundation
import UIKit
import Supabase
import PostgREST
import Storage
import Observation

@Observable
final class ActivityDetailViewModel {
    var activity: Activity
    var reports: [Report] = []
    var isLoading = false
    var isSubmittingReport = false
    var errorMessage: String?

    /// Set after photo submission — SubmitReportView uses this to show the verdict screen
    var lastAIResult: AIVerificationResult?
    var lastAIExplanation: String?

    /// Called after any successful counted submission so global streak refreshes
    var onReportSubmitted: (() -> Void)?

    private let aiService = AIVerificationService.shared

    init(activity: Activity) {
        self.activity = activity
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
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    // MARK: - Photo report (challenge / assignment)

    func submitPhotoReport(image: UIImage, comment: String, isExcuse: Bool = false) async {
        isSubmittingReport = true
        errorMessage = nil
        lastAIResult = nil
        lastAIExplanation = nil
        defer { isSubmittingReport = false }

        do {
            // 1. Upload photo
            guard let jpeg = image.jpegData(compressionQuality: 0.8) else { return }
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
            var report: Report = try await supabase
                .from("reports")
                .insert(req)
                .select()
                .single()
                .execute()
                .value
            reports.insert(report, at: 0)

            // 3. AI verification
            if activity.type.hasAIVerification, let condition = activity.condition {
                let aiResponse = try await aiService.verify(
                    reportId:   report.id,
                    activityId: activity.id,
                    condition:  condition,
                    photoURL:   photoURL,
                    isExcuse:   isExcuse
                )

                // Determine result
                let resultEnum: AIVerificationResult
                if aiResponse.approved {
                    resultEnum = .approved
                } else if aiResponse.excused {
                    resultEnum = .excused
                } else {
                    resultEnum = .rejected
                }

                let resultStr = resultEnum.rawValue
                try await supabase
                    .from("reports")
                    .update(["ai_result": resultStr, "ai_explanation": aiResponse.explanation])
                    .eq("id", value: report.id.uuidString)
                    .execute()

                if let idx = reports.firstIndex(where: { $0.id == report.id }) {
                    reports[idx].aiResult      = resultEnum
                    reports[idx].aiExplanation = aiResponse.explanation
                }

                lastAIResult      = resultEnum
                lastAIExplanation = aiResponse.explanation

                switch resultEnum {
                case .approved:
                    if activity.frequency == .once { try await markCompleted() }
                    onReportSubmitted?()
                case .excused:
                    // Excuse accepted — activity stays active, streak not counted but not penalised
                    break
                default:
                    // Rejected — nothing
                    break
                }
            } else {
                // No AI needed — always counts
                lastAIResult = .notApplicable
                if activity.frequency == .once { try await markCompleted() }
                onReportSubmitted?()
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
            if activity.frequency == .once { try await markCompleted() }
            onReportSubmitted?()
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
            var photoURL: String?
            if let image, let jpeg = image.jpegData(compressionQuality: 0.8) {
                let path = "\(activity.id.uuidString)/\(UUID().uuidString).jpg"
                try await supabase.storage
                    .from(Constants.Storage.reportsBucket)
                    .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg"))
                photoURL = try supabase.storage
                    .from(Constants.Storage.reportsBucket)
                    .getPublicURL(path: path)
                    .absoluteString
            }

            let newProgress = activity.goalProgress + value
            let req = CreateReportRequest(activityId: activity.id, photoURL: photoURL, progressValue: value)
            let report: Report = try await supabase
                .from("reports")
                .insert(req)
                .select()
                .single()
                .execute()
                .value
            reports.insert(report, at: 0)

            try await supabase
                .from("activities")
                .update(["goal_progress": newProgress])
                .eq("id", value: activity.id.uuidString)
                .execute()
            activity.goalProgress = newProgress

            if let target = activity.goalTarget, newProgress >= target {
                try await markCompleted()
            }
            onReportSubmitted?()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func markCompleted() async throws {
        try await supabase
            .from("activities")
            .update(["status": "completed"])
            .eq("id", value: activity.id.uuidString)
            .execute()
        activity.status = .completed
    }
}
