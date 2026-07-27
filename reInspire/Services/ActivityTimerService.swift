import Foundation
import Observation

@MainActor
@Observable
final class ActivityTimerService {
    static let shared = ActivityTimerService()

    struct Session: Codable, Equatable {
        let activityId: UUID
        let userId: UUID
        let title: String
        let targetMinutes: Double?
        var startedAt: Date?
        var accumulatedSeconds: TimeInterval
    }

    private(set) var session: Session?
    private(set) var submittingActivityId: UUID?
    private let cacheKey = "activeActivityTimer"

    private init() {
        session = DiskCache.load(Session.self, key: cacheKey)
    }

    var activeActivityId: UUID? { session?.activityId }

    func isActive(_ activityId: UUID) -> Bool {
        session?.activityId == activityId
    }

    func isRunning(_ activityId: UUID) -> Bool {
        session?.activityId == activityId && session?.startedAt != nil
    }

    func isSubmitting(_ activityId: UUID) -> Bool {
        submittingActivityId == activityId
    }

    func elapsedSeconds(for activityId: UUID, at date: Date = Date()) -> TimeInterval {
        guard let session, session.activityId == activityId else { return 0 }
        let running = session.startedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0
        return max(0, session.accumulatedSeconds + running)
    }

    /// Starts, pauses, or resumes one timer. A second task cannot silently
    /// replace an unfinished session.
    @discardableResult
    func toggle(_ activity: Activity) -> Bool {
        guard let userId = AuthService.shared.currentUser?.id else { return false }
        guard submittingActivityId != activity.id else { return false }

        if var current = session {
            guard current.activityId == activity.id else { return false }
            if let startedAt = current.startedAt {
                current.accumulatedSeconds += max(0, Date().timeIntervalSince(startedAt))
                current.startedAt = nil
            } else {
                current.startedAt = Date()
            }
            session = current
        } else {
            session = Session(
                activityId: activity.id,
                userId: userId,
                title: activity.title,
                targetMinutes: activity.goalTarget,
                startedAt: Date(),
                accumulatedSeconds: 0
            )
        }

        persistAndPublish()
        return true
    }

    /// Pauses before submission and returns the measured minutes. The session
    /// remains persisted until the server accepts it, so a network error cannot
    /// erase the user's time.
    func minutesForSubmission(_ activityId: UUID) -> Double? {
        guard submittingActivityId == nil else { return nil }
        guard var current = session, current.activityId == activityId else { return nil }
        if let startedAt = current.startedAt {
            current.accumulatedSeconds += max(0, Date().timeIntervalSince(startedAt))
            current.startedAt = nil
            session = current
            persistAndPublish()
        }
        let minutes = current.accumulatedSeconds / 60
        guard minutes > 0 else { return nil }
        submittingActivityId = activityId
        return minutes
    }

    func completeSubmission(_ activityId: UUID) {
        guard session?.activityId == activityId else { return }
        submittingActivityId = nil
        session = nil
        DiskCache.remove(key: cacheKey)
        LiveActivityService.shared.clearTimer()
    }

    func cancelSubmission(_ activityId: UUID) {
        guard submittingActivityId == activityId else { return }
        submittingActivityId = nil
    }

    func reset(_ activityId: UUID) {
        guard session?.activityId == activityId else { return }
        submittingActivityId = nil
        session = nil
        DiskCache.remove(key: cacheKey)
        LiveActivityService.shared.clearTimer()
    }

    func restoreLiveActivity() {
        guard let current = session else { return }
        guard current.userId == AuthService.shared.currentUser?.id else {
            session = nil
            DiskCache.remove(key: cacheKey)
            LiveActivityService.shared.clearTimer()
            return
        }
        publish(current)
    }

    private func persistAndPublish() {
        guard let session else { return }
        DiskCache.save(session, key: cacheKey)
        publish(session)
    }

    private func publish(_ session: Session) {
        LiveActivityService.shared.setTimer(
            taskId: session.activityId,
            title: session.title,
            startedAt: session.startedAt,
            accumulatedSeconds: session.accumulatedSeconds,
            targetMinutes: session.targetMinutes
        )
    }
}
