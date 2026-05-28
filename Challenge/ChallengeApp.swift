import SwiftUI

@main
struct ChallengeApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    private let authService = AuthService.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authService)
                .task {
                    await NotificationService.shared.requestPermission()
                }
        }
    }
}

struct RootView: View {
    @Environment(AuthService.self) private var authService

    var body: some View {
        if authService.isAuthenticated {
            MainTabView()
        } else {
            AuthView()
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
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
        print("APNs registration failed: \(error)")
    }
}
