import Foundation
import Supabase
import PostgREST
import Observation
import os.log

/// A write to `activities` that can be performed now or replayed later. Creates
/// carry a client id so edits/deletes of an offline-created row stay coherent;
/// every other change is a targeted column update. Replayed in FIFO order, so a
/// create always precedes the edits/deletes that reference it.
enum PendingMutation: Codable {
    case createActivity(CreateActivityRequest)
    case updateActivity(id: UUID, fields: [String: JSONValue])
    case deleteActivity(id: UUID, log: ActivityDeletionLog)
}

/// Row written to `activity_deletions` before an activity is removed.
struct ActivityDeletionLog: Codable {
    let userId: UUID
    let activityId: UUID
    let title: String
    let type: String
    let reason: String

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case activityId = "activity_id"
        case title, type, reason
    }
}

/// Owns the offline write queue for `activities` and orchestrates the
/// reconnect drain (mutations -> deferred photo verifications). Every activity
/// mutation funnels through `perform`, which runs it immediately when online
/// and persists it for replay when not. The server stays authoritative; this
/// only buys offline tolerance and crash-safe retries.
@MainActor
@Observable
final class SyncService {
    static let shared = SyncService()

    /// Pending writes the user hasn't been able to push yet (drives a subtle
    /// "N changes waiting" affordance if a screen wants it).
    private(set) var pendingCount = 0

    private var queue: [PendingMutation] = []
    private let logger = Logger(subsystem: "com.reinspire", category: "SyncService")
    private var draining = false
    private var loaded = false

    private init() {}

    // MARK: - Persistence (per-user so a sign-out can't replay under a new session)

    private var cacheKey: String? {
        AuthService.shared.currentUser.map { "pendingMutations_\($0.id.uuidString)" }
    }

    private func loadIfNeeded() {
        // Stay unloaded until a user (hence a cache key) exists, so a pre-login
        // call can't latch an empty queue and shadow real pending writes.
        guard !loaded, let key = cacheKey else { return }
        loaded = true
        queue = DiskCache.load([PendingMutation].self, key: key) ?? []
        pendingCount = queue.count
    }

    private func persist() {
        pendingCount = queue.count
        guard let key = cacheKey else { return }
        DiskCache.save(queue, key: key)
    }

    // MARK: - Public API

    /// Run a mutation now if we can; queue it for replay if the write fails or
    /// we are offline. Optimistic local state is the caller's responsibility.
    func perform(_ mutation: PendingMutation) async {
        loadIfNeeded()
        if NetworkMonitor.shared.isOnline {
            do {
                try await execute(mutation)
                return
            } catch {
                logger.error("mutation failed, queueing for replay: \(error)")
            }
        }
        queue.append(mutation)
        persist()
    }

    /// Drain everything that accumulated offline: queued writes first (so any
    /// rows the photos depend on exist), then deferred photo verifications.
    /// Posts `.offlineSyncCompleted` only when work actually flushed, so the
    /// reload it triggers can't feed back into an endless sync loop.
    func syncNow() async {
        loadIfNeeded()
        let drained = await drainMutations()
        let photos = await PendingPhotoStore.shared.drain()
        if drained > 0 || photos > 0 {
            NotificationCenter.default.post(name: .offlineSyncCompleted, object: nil)
        }
    }

    @discardableResult
    private func drainMutations() async -> Int {
        guard !draining, NetworkMonitor.shared.isOnline else { return 0 }
        draining = true
        defer { draining = false }
        var flushed = 0
        while let head = queue.first {
            do {
                try await execute(head)
                queue.removeFirst()
                persist()
                flushed += 1
            } catch {
                // Likely still offline / transient -- stop and retry on the next
                // reconnect rather than dropping the user's change.
                logger.error("drain stopped at head mutation: \(error)")
                break
            }
        }
        return flushed
    }

    // MARK: - Execution

    private func execute(_ mutation: PendingMutation) async throws {
        switch mutation {
        case .createActivity(let req):
            try await supabase.from("activities").insert(req).execute()

        case .updateActivity(let id, let fields):
            try await supabase
                .from("activities")
                .update(fields)
                .eq("id", value: id.uuidString)
                .execute()

        case .deleteActivity(let id, let log):
            // Best-effort audit row; never block the delete on it.
            _ = try? await supabase.from("activity_deletions").insert(log).execute()
            try await supabase
                .from("activities")
                .delete()
                .eq("id", value: id.uuidString)
                .execute()
        }
    }
}

extension Notification.Name {
    /// Posted on the main actor after the offline queues finish draining, so
    /// view models can reload from the now-authoritative server state.
    static let offlineSyncCompleted = Notification.Name("offlineSyncCompleted")
}
