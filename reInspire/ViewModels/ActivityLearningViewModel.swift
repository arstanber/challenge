import Foundation
import Observation
import Supabase

@MainActor
@Observable
final class ActivityLearningViewModel {
    private(set) var guide: LearningGuide?
    private(set) var isLoading = false
    var errorMessage: String?

    private let activity: Activity
    private let service = LearningGuideService.shared
    private var hasLoaded = false

    init(activity: Activity) {
        self.activity = activity
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await load(forceRefresh: false)
    }

    func refresh() async {
        await load(forceRefresh: true)
    }

    private func load(forceRefresh: Bool) async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            guide = try await service.guide(for: activity, forceRefresh: forceRefresh)
            hasLoaded = true
        } catch let error as FunctionsError {
            if case .httpError(let status, _) = error, status == 403 {
                errorMessage = String(localized: "Обучение доступно только в Max")
            } else {
                errorMessage = String(localized: "Не удалось создать обучение. Попробуйте позже.")
            }
        } catch {
            errorMessage = String(localized: "Не удалось создать обучение. Попробуйте позже.")
        }
    }
}
