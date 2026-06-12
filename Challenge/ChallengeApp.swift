import SwiftUI
import os.log
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct ChallengeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let authService = AuthService.shared
    private let storeService = StoreService.shared

    init() {
        AnalyticsService.shared.start()
        AnalyticsService.shared.track(.appLaunched)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authService)
                .task {
                    CloudSyncService.shared.start()
                    await NotificationService.shared.requestPermission()
                }
                .onOpenURL { url in
                    #if canImport(GoogleSignIn)
                    GIDSignIn.sharedInstance.handle(url)
                    #endif
                }
        }
    }
}

struct RootView: View {
    @Environment(AuthService.self) private var authService
    @AppStorage("appTheme") private var appTheme = AppColorTheme.light.rawValue
    @AppStorage(AppPrefs.Key.timeFormat) private var timeFormat = AppPrefs.Option.h24

    var body: some View {
        Group {
            if authService.isRestoring {
                LoadingView()
            } else if authService.isAuthenticated {
                if authService.needsWelcomeIntro {
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
    }

    private func locale(hourCycle: String) -> Locale {
        var comps = Locale.Components(locale: .current)
        comps.hourCycle = hourCycle == AppPrefs.Option.h12 ? .oneToTwelve : .zeroToTwentyThree
        return Locale(components: comps)
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    private let logger = Logger(subsystem: "com.challenge", category: "AppDelegate")
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
