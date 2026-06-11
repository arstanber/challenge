import Foundation
import Observation
import os.log

/// Mirrors the user's app settings to iCloud key-value storage so they follow
/// the user across devices. Task data lives in Supabase and syncs through the
/// account; this covers the local-only preferences (theme, units, toggles).
///
/// Last-writer-wins: external iCloud changes are pulled into UserDefaults,
/// local changes are pushed on every defaults change. The `isApplyingRemote`
/// flag breaks the pull -> didChange -> push echo.
@MainActor
@Observable
final class CloudSyncService {
    static let shared = CloudSyncService()

    enum Status {
        case synced
        case unavailable

        var title: String {
            switch self {
            case .synced:      return "Синхронизировано"
            case .unavailable: return "Недоступно"
            }
        }
    }

    private(set) var status: Status = .unavailable

    private let store = NSUbiquitousKeyValueStore.default
    private let defaults = UserDefaults.standard
    private let logger = Logger(subsystem: "com.challenge", category: "CloudSyncService")
    private var isApplyingRemote = false
    private var started = false

    /// Settings mirrored to iCloud. Keep in sync with the @AppStorage keys
    /// in SettingsView / HomeView.
    private static let syncedKeys = [
        "appTheme", "timeFormat", "units", "weekStart", "defaultView",
        Haptics.enabledKey, "groupCompleted", "strictMode", "requirePhotoVerification"
    ]

    private init() {}

    func start() {
        guard !started else { return }
        started = true

        refreshAvailability()
        pullAll()
        pushAll()

        // External changes from another device (or initial server download).
        Task { [weak self] in
            let changes = NotificationCenter.default
                .notifications(named: NSUbiquitousKeyValueStore.didChangeExternallyNotification)
                .map { _ in () }
            for await _ in changes {
                self?.refreshAvailability()
                self?.pullAll()
            }
        }

        // Local changes: push the mirrored keys up.
        Task { [weak self] in
            let changes = NotificationCenter.default
                .notifications(named: UserDefaults.didChangeNotification)
                .map { _ in () }
            for await _ in changes {
                guard let self, !self.isApplyingRemote else { continue }
                self.pushAll()
            }
        }
    }

    /// iCloud KVS is available only when the user is signed into iCloud.
    private func refreshAvailability() {
        status = FileManager.default.ubiquityIdentityToken != nil ? .synced : .unavailable
    }

    private func pullAll() {
        isApplyingRemote = true
        defer { isApplyingRemote = false }
        for key in Self.syncedKeys {
            guard let remote = store.object(forKey: key) else { continue }
            let local = defaults.object(forKey: key)
            if local == nil || !isEqualPlist(remote, local!) {
                defaults.set(remote, forKey: key)
            }
        }
    }

    private func pushAll() {
        var changed = false
        for key in Self.syncedKeys {
            guard let local = defaults.object(forKey: key) else { continue }
            let remote = store.object(forKey: key)
            if remote == nil || !isEqualPlist(local, remote!) {
                store.set(local, forKey: key)
                changed = true
            }
        }
        if changed, !store.synchronize() {
            logger.error("iCloud KVS synchronize() returned false -- check the ubiquity entitlement")
            refreshAvailability()
        }
    }

    private func isEqualPlist(_ a: Any, _ b: Any) -> Bool {
        (a as? NSObject)?.isEqual(b) ?? false
    }
}
