import Foundation
import UIKit
import Supabase
import PostgREST
import Storage
import Observation
import os.log

/// A photo report captured while offline. The JPEG lives on disk; on the next
/// reconnect it is uploaded, a report row is inserted, and AI verification runs
/// -- exactly the online flow, just deferred. Stored under Application Support
/// (not Caches) so the system never purges a proof the user is waiting on.
private struct PendingPhoto: Codable, Identifiable {
    let id: UUID
    let activityId: UUID
    let condition: String
    let isExcuse: Bool
    let comment: String?
    let photoFile: String
    let isOnceTask: Bool
    let createdAt: Date
}

private struct DeferredReportRequest: Encodable {
    let id: UUID
    let activityId: UUID
    let photoURL: String
    let comment: String?

    enum CodingKeys: String, CodingKey {
        case id
        case activityId = "activity_id"
        case photoURL = "photo_url"
        case comment
    }
}

@MainActor
@Observable
final class PendingPhotoStore {
    static let shared = PendingPhotoStore()

    private(set) var pendingCount = 0

    private let logger = Logger(subsystem: "com.reinspire", category: "PendingPhotoStore")
    private let aiService = AIVerificationService.shared
    private var entries: [PendingPhoto] = []
    private var loaded = false
    private var draining = false

    private init() {}

    // MARK: - Storage location

    private static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("PendingPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    private var indexURL: URL { Self.directory.appendingPathComponent("index.json") }

    private func loadIfNeeded() {
        guard !loaded else { return }
        loaded = true
        if let data = try? Data(contentsOf: indexURL),
           let decoded = try? JSONDecoder().decode([PendingPhoto].self, from: data) {
            entries = decoded
        }
        pendingCount = entries.count
    }

    private func persist() {
        pendingCount = entries.count
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(entries) {
            try? data.write(to: indexURL, options: .atomic)
        }
    }

    // MARK: - Enqueue

    /// Save a captured photo report for later verification. Returns false only
    /// if the image can't be encoded -- the caller treats a queued report as
    /// optimistically done.
    @discardableResult
    func enqueue(image: UIImage, activity: Activity, isExcuse: Bool, comment: String) -> Bool {
        loadIfNeeded()
        guard let jpeg = image.compressedForUpload() else { return false }
        let file = "\(UUID().uuidString).jpg"
        do {
            try jpeg.write(to: Self.directory.appendingPathComponent(file), options: .atomic)
        } catch {
            logger.error("could not write pending photo: \(error)")
            return false
        }
        let trimmed = activity.condition?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let entry = PendingPhoto(
            id: UUID(),
            activityId: activity.id,
            condition: trimmed.isEmpty ? activity.title : trimmed,
            isExcuse: isExcuse,
            comment: comment.isEmpty ? nil : comment,
            photoFile: file,
            isOnceTask: activity.frequency == .once,
            createdAt: Date()
        )
        entries.append(entry)
        persist()
        return true
    }

    // MARK: - Drain

    @discardableResult
    func drain() async -> Int {
        loadIfNeeded()
        guard !draining, NetworkMonitor.shared.isOnline else { return 0 }
        draining = true
        defer { draining = false }

        var flushed = 0
        for entry in entries {
            do {
                try await verify(entry)
                remove(entry)
                flushed += 1
            } catch {
                // Network blip mid-drain -- keep the rest for the next reconnect.
                logger.error("deferred verification failed for \(entry.id): \(error)")
                break
            }
        }
        return flushed
    }

    private func verify(_ entry: PendingPhoto) async throws {
        let fileURL = Self.directory.appendingPathComponent(entry.photoFile)
        let jpeg = try Data(contentsOf: fileURL)

        // 1. Upload the proof.
        let path = "\(entry.activityId.uuidString)/\(entry.id.uuidString).jpg"
        try await supabase.storage
            .from(Constants.Storage.reportsBucket)
            .upload(path, data: jpeg, options: FileOptions(contentType: "image/jpeg", upsert: true))
        let photoURL = try supabase.storage
            .from(Constants.Storage.reportsBucket)
            .getPublicURL(path: path)
            .absoluteString

        // 2. Insert the report (created_at reflects replay time, which is fine --
        //    the streak day is still the user's local day if they reconnect same day).
        let req = DeferredReportRequest(
            id: entry.id,
            activityId: entry.activityId,
            photoURL: photoURL,
            comment: entry.comment
        )
        let report: Report = try await supabase
            .from("reports")
            .upsert(req, onConflict: "id")
            .select()
            .single()
            .execute()
            .value

        // 3. AI verification. Photo reports stay pending until the server writes
        //    an explicit approved/excused/rejected verdict. A transient failure
        //    must never turn an unverified proof into a completed task.
        do {
            let resp = try await aiService.verify(
                reportId: report.id,
                activityId: entry.activityId,
                condition: entry.condition,
                photoURL: photoURL,
                isExcuse: entry.isExcuse
            )
            if let remaining = resp.remaining {
                RateLimiterService.shared.syncRemaining(remaining, for: .verifyReport)
            }
            let rejected = !resp.approved && !resp.excused
            if rejected {
                TaskEngine.shared.clearOptimisticDone(entry.activityId)
            } else if resp.approved && entry.isOnceTask {
                await SyncService.shared.perform(
                    .updateActivity(id: entry.activityId, fields: ["status": .string("completed")])
                )
            }
        } catch {
            TaskEngine.shared.clearOptimisticDone(entry.activityId)
            logger.error("deferred AI verify unavailable for \(entry.id): \(error)")
            throw error
        }

        await TaskEngine.shared.noteReportChanged(activityId: entry.activityId)
    }

    private func remove(_ entry: PendingPhoto) {
        try? FileManager.default.removeItem(at: Self.directory.appendingPathComponent(entry.photoFile))
        entries.removeAll { $0.id == entry.id }
        persist()
    }
}
