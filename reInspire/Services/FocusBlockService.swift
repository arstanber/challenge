import Foundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.reinspire", category: "FocusBlockService")

#if canImport(FamilyControls)
import FamilyControls
import ManagedSettings

// MARK: - Focus / Screen Time blocking (#11)
// Requires the `com.apple.developer.family-controls` entitlement (Apple-approved)
// and a real device. Compiles against the SDK; authorization is runtime-gated.

@MainActor
@Observable
final class FocusBlockService {
    static let shared = FocusBlockService()

    var selection = FamilyActivitySelection()
    var isAuthorized = false
    var isBlocking = false

    private let store = ManagedSettingsStore()
    private let defaults = UserDefaults(suiteName: WidgetDataStore.appGroup) ?? .standard
    private let selectionKey = "focus_selection"

    private init() {
        loadSelection()
        isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
    }

    // MARK: - Authorization

    func requestAuthorization() async {
        do {
            try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
            isAuthorized = AuthorizationCenter.shared.authorizationStatus == .approved
        } catch {
            logger.error("FocusBlockService auth error: \(error)")
            isAuthorized = false
        }
    }

    // MARK: - Selection persistence

    func saveSelection() {
        if let data = try? JSONEncoder().encode(selection) {
            defaults.set(data, forKey: selectionKey)
        }
    }

    private func loadSelection() {
        if let data = defaults.data(forKey: selectionKey),
           let sel = try? JSONDecoder().decode(FamilyActivitySelection.self, from: data) {
            selection = sel
        }
    }

    var hasSelection: Bool {
        !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty
    }

    // MARK: - Blocking

    /// Shields the selected apps/categories for the duration of a focus session.
    func startBlocking() {
        guard isAuthorized else { return }
        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty
            ? nil
            : .specific(selection.categoryTokens)
        isBlocking = true
    }

    func stopBlocking() {
        store.shield.applications = nil
        store.shield.applicationCategories = nil
        isBlocking = false
    }
}
#endif
