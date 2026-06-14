import SwiftUI

#if canImport(FamilyControls)
import FamilyControls

// MARK: - Focus Mode (#11)
// Block distracting apps during a habit/work session.

struct FocusModeView: View {
    @State private var service = FocusBlockService.shared
    @State private var showPicker = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                header

                if !service.isAuthorized {
                    authPrompt
                } else {
                    pickerCard
                    blockToggle
                }
            }
            .padding(22)
            .readableWidth()
        }
        .background(Color.white)
        .navigationTitle("Focus Mode")
        .navigationBarTitleDisplayMode(.inline)
        .familyActivityPicker(isPresented: $showPicker, selection: $service.selection)
        .onChange(of: service.selection) { _, _ in service.saveSelection() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            Text("🎯").font(.system(size: 56))
            Text("Block distractions")
                .font(.manrope(.extraBold, size: 22))
            Text("Pick apps to shield while you focus on your activities.")
                .font(.manrope(.medium, size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var authPrompt: some View {
        Button {
            Haptics.tap()
            Task { await service.requestAuthorization() }
        } label: {
            Text("Enable Screen Time access")
                .font(.manrope(.bold, size: 16))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(hex: "4580FF")))
        }
    }

    private var pickerCard: some View {
        Button { showPicker = true } label: {
            HStack {
                Image(systemName: "apps.iphone")
                    .foregroundStyle(Color(hex: "4580FF"))
                Text(service.hasSelection ? "Edit blocked apps" : "Choose apps to block")
                    .font(.manrope(.bold, size: 15))
                    .foregroundColor(.black)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.black.opacity(0.3))
            }
            .padding(16)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.04)))
        }
        .buttonStyle(.haptic)
    }

    private var blockToggle: some View {
        Button {
            if service.isBlocking { Haptics.warning(); service.stopBlocking() }
            else { Haptics.success(); service.startBlocking() }
        } label: {
            Text(service.isBlocking ? "Stop focus session" : "Start focus session")
                .font(.manrope(.bold, size: 16))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(service.isBlocking ? Color(hex: "FF3B30") : Color(hex: "2FB873"))
                )
        }
        .disabled(!service.hasSelection)
        .opacity(service.hasSelection ? 1 : 0.5)
    }
}
#else
// Fallback when FamilyControls isn't available.
struct FocusModeView: View {
    var body: some View {
        ContentUnavailableView("Focus Mode unavailable",
                               systemImage: "moon.zzz",
                               description: Text("Screen Time controls aren't available on this build."))
    }
}
#endif
