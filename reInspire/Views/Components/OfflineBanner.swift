import SwiftUI

/// Thin top banner shown while the device is offline. Reassures the user that
/// their taps are saved locally and will sync, rather than leaving them
/// guessing why a write "didn't take".
struct OfflineBanner: View {
    @State private var monitor = NetworkMonitor.shared
    @State private var sync = SyncService.shared

    private var pending: Int { sync.pendingCount }

    var body: some View {
        Group {
            if !monitor.isOnline {
                HStack(spacing: 8) {
                    Image(systemName: "wifi.slash")
                        .font(.system(size: 13, weight: .semibold))
                    Text(pending > 0
                         ? "Нет сети -- \(pending) изм. синхронизируем позже"
                         : "Нет сети -- изменения сохраняются локально")
                        .font(.manrope(.semiBold, size: 13))
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity)
                .background(Color(hex: "2C2C2E"))
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: monitor.isOnline)
    }
}
