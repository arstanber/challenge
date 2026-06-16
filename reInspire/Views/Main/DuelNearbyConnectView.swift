import SwiftUI

/// Shake-to-connect for duels. Two phones nearby: one player creates the duel
/// (picks the length) and shares its code over the local link, the other joins
/// automatically. Mirrors the family NearbyConnectView but on its own channel.
struct DuelNearbyConnectView: View {
    var onJoined: () async -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var service = FamilyConnectService(serviceType: "chlg-duel")
    @State private var duelService = DuelService.shared

    private enum Role { case undecided, create, join }
    @State private var role: Role = .undecided
    @State private var days = 7
    @State private var creating = false
    @State private var sharedCode: String?
    @State private var joined = false
    @State private var pulse = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                switch role {
                case .undecided: rolePicker
                default:         pairing
                }
            }
            .padding(.bottom, 24)
            .navigationTitle("Дуэль рядом")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(joined ? "Готово" : "Закрыть") { dismiss() }
                }
            }
            .onAppear { pulse = true }
            .onDisappear { service.stop() }
            .background(
                ShakeDetector { if role != .undecided && !joined { restartSearch() } }
            )
            .onChange(of: service.receivedCode) { _, code in
                guard role == .join, let code, !code.isEmpty else { return }
                Task {
                    if await duelService.joinDuel(code: code) {
                        joined = true; Haptics.success(); await onJoined()
                    }
                }
            }
            .onChange(of: service.didShareCode) { _, shared in
                if shared { joined = true; Haptics.success(); Task { await onJoined() } }
            }
        }
    }

    // MARK: Role picker

    private var rolePicker: some View {
        VStack(spacing: 16) {
            Spacer()
            Text("⚔️").font(.system(size: 52))
            Text("Соединитесь рядом")
                .font(.title3.bold())
            Text("Один создаёт дуэль, второй присоединяется. Потом потрясите оба телефона.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 28)
            Spacer()
            Button { Haptics.tap(); role = .create } label: {
                Label("Создать дуэль", systemImage: "plus.circle.fill")
                    .font(.headline).frame(maxWidth: .infinity).frame(height: 54)
                    .background(Capsule().fill(Color(hex: "0048E2")))
                    .foregroundStyle(.white)
            }
            Button { Haptics.tap(); role = .join; startSearch() } label: {
                Label("Присоединиться", systemImage: "wave.3.right")
                    .font(.headline).frame(maxWidth: .infinity).frame(height: 54)
                    .background(Capsule().fill(Color(hex: "0048E2").opacity(0.15)))
                    .foregroundStyle(Color(hex: "0048E2"))
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: Pairing

    private var pairing: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                ForEach(0..<3) { i in
                    Circle()
                        .stroke(Color(hex: "0048E2").opacity(0.3), lineWidth: 2)
                        .frame(width: 90 + CGFloat(i) * 50, height: 90 + CGFloat(i) * 50)
                        .scaleEffect(pulse ? 1.1 : 0.9)
                        .opacity(pulse ? 0.2 : 0.7)
                        .animation(.easeInOut(duration: 1.2).repeatForever().delay(Double(i) * 0.2), value: pulse)
                }
                Image(systemName: joined ? "checkmark.circle.fill" : "iphone.gen3.radiowaves.left.and.right")
                    .font(.system(size: 46, weight: .semibold))
                    .foregroundStyle(Color(hex: "0048E2"))
            }
            .frame(height: 220)

            Text(statusTitle).font(.title3.bold()).multilineTextAlignment(.center)
            Text(statusSubtitle)
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).padding(.horizontal, 30)

            if role == .create && sharedCode == nil {
                Stepper("Дней: \(days)", value: $days, in: 3...90)
                    .padding(.horizontal, 30)
            }

            Spacer()

            if role == .create && sharedCode == nil {
                Button {
                    Haptics.heavy(); createAndShare()
                } label: {
                    Label(creating ? "Создаю..." : "Создать и искать", systemImage: "wave.3.right")
                        .font(.headline).frame(maxWidth: .infinity).frame(height: 54)
                        .background(Capsule().fill(Color(hex: "0048E2")))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 24)
                .disabled(creating)
            }
        }
    }

    private var statusTitle: String {
        if joined { return "Соединено!" }
        switch service.phase {
        case .searching:  return "Ищу рядом..."
        case .connecting: return "Подключаюсь к \(service.peerName ?? "устройству")..."
        case .failed:     return "Не удалось соединить"
        default:          return role == .create ? "Создай дуэль" : "Поднеси телефоны"
        }
    }

    private var statusSubtitle: String {
        if joined { return "Дуэль началась. Можешь закрыть экран." }
        if service.phase == .failed { return "Поднесите телефоны ближе и потрясите оба ещё раз." }
        return role == .create
            ? "Выбери длину дуэли и нажми кнопку, затем потрясите оба телефона."
            : "Потрясите оба телефона рядом, чтобы присоединиться к дуэли друга."
    }

    // MARK: Actions

    private func createAndShare() {
        creating = true
        Task {
            if let code = await duelService.createDuel(days: days) {
                sharedCode = code
                service.start(sharingCode: code)
            }
            creating = false
        }
    }

    private func startSearch() { service.start(sharingCode: nil) }

    private func restartSearch() {
        Haptics.heavy()
        service.start(sharingCode: role == .create ? sharedCode : nil)
    }
}

/// Reusable shake detector (responder-chain motion event).
private struct ShakeDetector: UIViewRepresentable {
    let onShake: () -> Void

    final class Inner: UIView {
        var onShake: () -> Void = {}
        override var canBecomeFirstResponder: Bool { true }
        override func didMoveToWindow() {
            super.didMoveToWindow(); becomeFirstResponder()
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
