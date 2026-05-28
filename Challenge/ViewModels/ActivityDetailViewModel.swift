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

    private let aiService = AIVerificationService.shared

    init(activity: Activity) {
        self.activity = activity
    }

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

    func submitPhotoReport(image: UIImage, comment: String) async {
        isSubmittingReport = true
        errorMessage = nil
        do {
            // 1. Upload photo to Supabase Storage
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

            // 3. AI verification if applicable
            if activity.type.hasAIVerification, let condition = activity.condition {
                let aiResponse = try await aiService.verify(
                    reportId: report.id,
                    activityId: activity.id,
                    condition: condition,
                    photoURL: photoURL
                )
                let resultStr = aiResponse.approved ? "approved" : "rejected"
                try await supabase
                    .from("reports")
                    .update(["ai_result": resultStr, "ai_explanation": aiResponse.explanation])
                    .eq("id", value: report.id.uuidString)
                    .execute()
                if let idx = reports.firstIndex(where: { $0.id == report.id }) {
                    reports[idx].aiResult = aiResponse.approved ? .approved : .rejected
                    reports[idx].aiExplanation = aiResponse.explanation
                }
                if aiResponse.approved { await updateStreak() }
            } else {
                await updateStreak()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmittingReport = false
    }

    func submitTaskReport() async {
        isSubmittingReport = true
        errorMessage = nil
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
            await updateStreak()
            if activity.frequency == .once {
                try await supabase
                    .from("activities")
                    .update(["status": "completed"])
                    .eq("id", value: activity.id.uuidString)
                    .execute()
                activity.status = .completed
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmittingReport = false
    }

    func submitGoalProgress(value: Double, image: UIImage?) async {
        isSubmittingReport = true
        errorMessage = nil
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
                try await supabase
                    .from("activities")
                    .update(["status": "completed"])
                    .eq("id", value: activity.id.uuidString)
                    .execute()
                activity.status = .completed
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isSubmittingReport = false
    }

    private func updateStreak() async {
        let newStreak = activity.streakCurrent + 1
        let newBest = max(newStreak, activity.streakBest)
        do {
            try await supabase
                .from("activities")
                .update(["streak_current": newStreak, "streak_best": newBest])
                .eq("id", value: activity.id.uuidString)
                .execute()
            activity.streakCurrent = newStreak
            activity.streakBest = newBest
        } catch {
            print("Streak update failed: \(error)")
        }
    }
}
