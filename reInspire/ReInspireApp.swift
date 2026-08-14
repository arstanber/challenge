import SwiftUI
import StoreKit
import os.log
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct ReInspireApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let authService = AuthService.shared
    private let storeService = StoreService.shared

    init() {
        AnalyticsService.shared.start()
        AnalyticsService.shared.track(.appLaunched)
        storeService.configure()
    }

    /// Parse a family invite deep link and stash the code for the join prompt.
    /// Handles reinspire://join?code=XXX and https://thechallenges.app/join?code=XXX
    /// (and the /join/XXX path form).
    static func handleInviteLink(_ url: URL) {
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let isJoin = (url.host == "join") || url.path.contains("join")
        guard isJoin else { return }
        var code = comps?.queryItems?.first(where: { $0.name == "code" })?.value
        if code == nil {
            let last = url.lastPathComponent
            if !last.isEmpty, last != "join", last != "/" { code = last }
        }
        guard let code, !code.isEmpty else { return }
        AuthService.shared.pendingFamilyCode = code.uppercased()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authService)
                .task {
                    CloudSyncService.shared.start()
                    NetworkMonitor.shared.start()
                    // Flush anything queued during a previous offline session.
                    await SyncService.shared.syncNow()
                    // Refresh the APNs token for already-granted users; the
                    // permission PROMPT is asked contextually on the push
                    // onboarding page, not on cold start.
                    await NotificationService.shared.registerIfAuthorized()
                }
                .onOpenURL { url in
                    #if canImport(GoogleSignIn)
                    if GIDSignIn.sharedInstance.handle(url) { return }
                    #endif
                    Self.handleInviteLink(url)
                }
        }
    }
}

struct RootView: View {
    @Environment(AuthService.self) private var authService
    @Environment(\.requestReview) private var requestReview
    @State private var reviewManager = ReviewRequestManager.shared
    @AppStorage("appTheme") private var appTheme = AppColorTheme.light.rawValue
    @AppStorage(AppPrefs.Key.timeFormat) private var timeFormat = AppPrefs.Option.h24

    var body: some View {
        Group {
            if authService.isRestoring {
                LoadingView()
            } else if authService.isAuthenticated {
                if authService.currentUser?.needsChildCredentials == true {
                    // A PIN child must register a real email + password first.
                    ChildSetCredentialsView()
                } else if authService.needsWelcomeIntro {
                    // One-time "Week on us" trial intro right after registration.
                    WeekOnUsView { authService.needsWelcomeIntro = false }
                } else {
                    MainTabView()
                }
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: authService.isRestoring)
        .animation(.easeInOut(duration: 0.35), value: authService.needsWelcomeIntro)
        .preferredColorScheme(AppColorTheme(rawValue: appTheme)?.colorScheme)
        // 12/24h override for every DatePicker and .formatted() time in the app.
        // Reading `timeFormat` here makes the whole tree re-render on change.
        .environment(\.locale, locale(hourCycle: timeFormat))
        .onChange(of: reviewManager.requestSequence) { _, _ in
            Task { @MainActor in
                // Let the success screen or camera dismiss before StoreKit
                // presents its native rating sheet.
                try? await Task.sleep(for: .seconds(1.5))
                requestReview()
            }
        }
    }

    private func locale(hourCycle: String) -> Locale {
        var comps = Locale.Components(locale: .current)
        comps.hourCycle = hourCycle == AppPrefs.Option.h12 ? .oneToTwelve : .zeroToTwentyThree
        return Locale(components: comps)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    private let logger = Logger(subsystem: "com.reinspire", category: "AppDelegate")
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        guard let userId = AuthService.shared.currentUser?.id else { return }
        Task {
            await NotificationService.shared.saveAPNSToken(deviceToken, userId: userId)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        logger.error("APNs registration failed: \(error)")
    }
}
