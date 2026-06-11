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

    var body: some View {
        Group {
            if authService.isRestoring {
                LoadingView()
            } else if authService.isAuthenticated {
                MainTabView()
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut(duration: 0.35), value: authService.isRestoring)
        .preferredColorScheme(AppColorTheme(rawValue: appTheme)?.colorScheme)
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
