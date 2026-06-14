import SwiftUI

/// Shake-to-connect pairing screen. Both phones shake near each other; the
/// device with a family code shares it, the other joins automatically.
struct NearbyConnectView: View {
    /// The caller's family invite code if they have one (parent); nil otherwise.
    let myCode: String?
    /// Called after a successful pairing so the caller can refresh.
    var onJoined: () async -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var service = FamilyConnectService()
    @State private var joinVM = ProfileViewModel()
    @State private var joined = false
    @State private var pulse = false

    var body: some View {
        NavigationStack { content }
    }

    private var content: some View {
        VStack(spacing: 24) {
            Spacer()

            ZStack {
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(Color.purple.opacity(0.3), lineWidth: 2)
                        .frame(width: 90 + CGFloat(i) * 50, height: 90 + CGFloat(i) * 50)
                        .scaleEffect(pulse ? 1.1 : 0.9)
                        .opacity(pulse ? 0.2 : 0.7)
                        .animation(.easeInOut(duration: 1.2).repeatForever().delay(Double(i) * 0.2), value: pulse)
                }
                Image(systemName: iconName)
                    .font(.system(size: 48, weight: .semibold))
                    .foregroundStyle(.purple)
            }
            .frame(height: 240)

            Text(title).font(.title3.bold()).multilineTextAlignment(.center)
            Text(subtitle)
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Spacer()

            if !joined {
                Button {
                    Haptics.heavy()
                    service.start(sharingCode: myCode)
                } label: {
                    Label("Начать поиск", systemImage: "wave.3.right")
                        .font(.headline).frame(maxWidth: .infinity).frame(height: 54)
                        .background(Capsule().fill(Color.purple))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
                .disabled(service.phase == .searching || service.phase == .connecting)
            }
        }
        .padding(.bottom, 24)
        .background(
            // Shake to (re)start the search -- the "trясти телефон" trigger.
            ShakeToConnect { if !joined { Haptics.heavy(); service.start(sharingCode: myCode) } }
        )
        .onAppear { pulse = true }
        .onDisappear { service.stop() }
        .onChange(of: service.receivedCode) { _, code in
            guard let code, !code.isEmpty else { return }
            Task {
                await joinVM.joinFamily(code: code)
                joined = true
                Haptics.success()
                await onJoined()
            }
        }
        .onChange(of: service.didShareCode) { _, shared in
            if shared {
                joined = true
                Haptics.success()
                Task { await onJoined() }
            }
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button(joined ? "Готово" : "Закрыть") { dismiss() }
            }
        }
    }

    private var iconName: String {
        switch service.phase {
        case .success: return "checkmark.circle.fill"
        case .failed:  return "exclamationmark.triangle.fill"
        default:       return "iphone.gen3.radiowaves.left.and.right"
        }
    }

    private var title: String {
        if joined { return "Соединено!" }
        switch service.phase {
        case .idle:       return "Потрясите телефоны"
        case .searching:  return "Ищу рядом..."
        case .connecting: return "Подключаюсь к \(service.peerName ?? "устройству")..."
        case .success:    return "Соединено!"
        case .failed:     return "Не удалось соединить"
        }
    }

    private var subtitle: String {
        if joined { return "Готово. Можешь закрыть экран." }
        switch service.phase {
        case .failed: return "Поднесите телефоны ближе и потрясите оба ещё раз."
        default:
            return myCode == nil
                ? "Поднесите телефон к телефону родителя и потрясите оба."
                : "Поднесите телефон к телефону ребёнка и потрясите оба."
        }
    }
}

/// Reusable shake detector (the responder-chain motion event).
private struct ShakeToConnect: UIViewRepresentable {
    let onShake: () -> Void

    final class Inner: UIView {
        var onShake: () -> Void = {}
        override var canBecomeFirstResponder: Bool { true }
        override func didMoveToWindow() {
            super.didMoveToWindow()
            becomeFirstResponder()
        }
        override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
            if motion == .motionShake { onShake() }
        }
    }

    func makeUIView(context: Context) -> Inner {
        let v = Inner(); v.onShake = onShake; return v
    }
    func updateUIView(_ uiView: Inner, context: Context) { uiView.onShake = onShake }
}
