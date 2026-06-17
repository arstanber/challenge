import SwiftUI
import AuthenticationServices
import CoreMotion
import Combine

// MARK: - Physics Engine

final class P6PhysicsEngine: ObservableObject {
    @Published var positions: [CGPoint] = Array(repeating: .zero, count: 4)
    @Published var rotations: [Double] = [-5, 5, -5, 5]

    private var velocities: [CGPoint] = Array(repeating: .zero, count: 4)
    private var gravity: CGPoint = CGPoint(x: 0, y: 600)
    private var bounds: CGRect = .zero
    private let photoSize: CGFloat = 110
    private let restitution: CGFloat = 0.55
    private let damping: CGFloat = 0.994
    private var timer: Timer?
    private let motion = CMMotionManager()
    private(set) var stripPositions: [CGPoint] = []

    // Configure rest positions and physics bounds, then immediately start simulation
    func configure(screenWidth: CGFloat, topInset: CGFloat, cardTop: CGFloat) {
        let half = photoSize / 2
        bounds = CGRect(
            x: half,
            y: topInset + half + 10,
            width: screenWidth - photoSize,
            height: cardTop - topInset - photoSize - 10
        )
        let spacing: CGFloat = 6
        let totalW = CGFloat(4) * photoSize + CGFloat(3) * spacing
        let startX = (screenWidth - totalW) / 2 + half
        stripPositions = (0..<4).map { i in
            CGPoint(x: startX + CGFloat(i) * (photoSize + spacing),
                    y: cardTop - half - 12) // resting just above the popup edge
        }
        positions = stripPositions
        // Immediate scatter so photos spread out and respond to tilt without needing a shake
        for i in 0..<4 {
            velocities[i] = CGPoint(
                x: CGFloat.random(in: -260...260),
                y: CGFloat.random(in: -260...(-90))
            )
        }
        startSimulation() // always on — gravity responds to tilt immediately
    }

    // Shake = extra impulse burst; simulation is already running
    func shake() {
        for i in 0..<4 {
            velocities[i].x += CGFloat.random(in: -280...280)
            velocities[i].y += CGFloat.random(in: -400...(-150))
        }
    }

    // Stop simulation (call on view disappear)
    func stop() {
        timer?.invalidate(); timer = nil
        motion.stopDeviceMotionUpdates()
    }

    private func startSimulation() {
        guard timer == nil else { return }
        // CoreMotion gravity
        if motion.isDeviceMotionAvailable {
            motion.deviceMotionUpdateInterval = 1.0 / 60.0
            motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
                guard let self, let d = data else { return }
                self.gravity = CGPoint(x: CGFloat(d.gravity.x) * 900,
                                       y: CGFloat(-d.gravity.y) * 900)
            }
        }
        // Physics loop
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            self?.step()
        }
    }

    private func step() {
        let dt: CGFloat = 1.0 / 60.0
        let n = 4
        for i in 0..<n {
            // Gravity + damping
            velocities[i].x = (velocities[i].x + gravity.x * dt) * damping
            velocities[i].y = (velocities[i].y + gravity.y * dt) * damping
            positions[i].x += velocities[i].x * dt
            positions[i].y += velocities[i].y * dt
            // Spin
            rotations[i] += Double(velocities[i].x) * 0.03 * Double(dt)

            // Wall collisions
            let half = photoSize / 2
            if positions[i].x < bounds.minX + half {
                positions[i].x = bounds.minX + half
                velocities[i].x = abs(velocities[i].x) * restitution
            } else if positions[i].x > bounds.maxX + half {
                positions[i].x = bounds.maxX + half
                velocities[i].x = -abs(velocities[i].x) * restitution
            }
            if positions[i].y < bounds.minY {
                positions[i].y = bounds.minY
                velocities[i].y = abs(velocities[i].y) * restitution
            } else if positions[i].y > bounds.maxY {
                positions[i].y = bounds.maxY
                velocities[i].y = -abs(velocities[i].y) * restitution
            }
        }
        // Photo–photo collisions
        for i in 0..<n {
            for j in (i+1)..<n {
                let dx = positions[j].x - positions[i].x
                let dy = positions[j].y - positions[i].y
                let d2 = dx*dx + dy*dy
                guard d2 < photoSize*photoSize, d2 > 0.01 else { continue }
                let d = sqrt(d2)
                let nx = dx/d, ny = dy/d
                let overlap = (photoSize - d) / 2
                positions[i].x -= nx * overlap; positions[i].y -= ny * overlap
                positions[j].x += nx * overlap; positions[j].y += ny * overlap
                let dvx = velocities[j].x - velocities[i].x
                let dvy = velocities[j].y - velocities[i].y
                let dot = dvx*nx + dvy*ny
                guard dot < 0 else { continue }
                let imp = dot * restitution
                velocities[i].x += imp*nx; velocities[i].y += imp*ny
                velocities[j].x -= imp*nx; velocities[j].y -= imp*ny
            }
        }
    }
}

// MARK: - Shake detector (UIKit bridge)

private struct ShakeDetector: UIViewRepresentable {
    let onShake: () -> Void
    class Inner: UIView {
        var onShake: () -> Void = {}
        override var canBecomeFirstResponder: Bool { true }
        override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
            if motion == .motionShake { onShake() }
        }
    }
    func makeUIView(context: Context) -> Inner {
        let v = Inner(); v.onShake = onShake
        DispatchQueue.main.async { v.becomeFirstResponder() }
        return v
    }
    func updateUIView(_ uiView: Inner, context: Context) { uiView.onShake = onShake }
}

// MARK: - Page 6: Registration / Sign in (final onboarding step)

struct GetStartedScreen: View {
    let onClose: () -> Void

    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @Environment(AuthService.self) private var authService
    @State private var vm = AuthViewModel()
    @State private var showEmailForm = false
    @State private var showChildSignIn = false
    @State private var keyboardHeight: CGFloat = 0
    @StateObject private var physics = P6PhysicsEngine()

    private let images = ["poster1", "poster2", "poster3", "poster4"]
    private let photoSize: CGFloat = 110
    private let photoRadius: CGFloat = 22

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.white.ignoresSafeArea()
                P6Blob()

                // Shake detector
                ShakeDetector { Haptics.heavy(); physics.shake() }
                    .frame(width: 0, height: 0)

                // Photos BEHIND the card
                ForEach(0..<images.count, id: \.self) { i in
                    Image(images[i])
                        .resizable()
                        .scaledToFill()
                        .frame(width: photoSize, height: photoSize)
                        .clipShape(RoundedRectangle(cornerRadius: photoRadius))
                        .rotationEffect(.degrees(physics.rotations[i]))
                        .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 5)
                        .position(physics.positions[i])
                        .appearEffect(delay: 0.08 + Double(i) * 0.08)
                }

                // UI stack ON TOP of photos
                VStack(spacing: 0) {
                    Text("reInspire.")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.black)
                        .lineSpacing(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 56)
                        .padding(.horizontal, 20)
                        .appearEffect(delay: 0.05)

                    Spacer()

                    if showEmailForm {
                        P6EmailCard(
                            vm: vm,
                            onBack: { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showEmailForm = false } }
                        )
                        .ignoresSafeArea(edges: .bottom)
                        // Lift the form above the keyboard so the password field
                        // stays visible while typing. The card extends past the
                        // safe area, so only the overlap beyond it needs lifting.
                        .offset(y: -max(0, keyboardHeight - geo.safeAreaInsets.bottom))
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    } else {
                        P6Card(
                            onClose: onClose,
                            onEmail: { withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showEmailForm = true } },
                            onApple: { Task { await vm.signInWithApple() } },
                            onGoogle: { Task { await vm.handleGoogleSignIn() } },
                            onChild: { Haptics.tap(); showChildSignIn = true },
                            errorMessage: vm.errorMessage
                        )
                        .ignoresSafeArea(edges: .bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .readableWidth(560)
            }
            .onAppear {
                physics.configure(
                    screenWidth: geo.size.width,
                    topInset: geo.safeAreaInsets.top,
                    cardTop: geo.size.height * 0.44
                )
            }
            .onDisappear {
                physics.stop()
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { notif in
                guard let frame = notif.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
                withAnimation(.easeOut(duration: 0.25)) { keyboardHeight = frame.height }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
                withAnimation(.easeOut(duration: 0.25)) { keyboardHeight = 0 }
            }
        }
        .onChange(of: authService.isAuthenticated) { _, isAuth in
            if isAuth {
                Haptics.success()
                hasSeenOnboarding = true
                AnalyticsService.shared.track(.onboardingCompleted)
            }
        }
        .onChange(of: vm.errorMessage) { _, newError in
            if newError != nil { Haptics.error() }
        }
        .sheet(isPresented: $showChildSignIn) {
            ChildSignInView().environment(authService)
        }
    }
}

// MARK: - Background blob

private struct P6Blob: View {
    var body: some View {
        GeometryReader { geo in
            Ellipse()
                .fill(Color(red: 0.0, green: 0.282, blue: 0.886).opacity(0.3))
                .frame(width: 712, height: 850)
                .offset(x: geo.size.width / 2 - 356, y: geo.size.height - 600)
                .blur(radius: 40)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Bottom sheet card

private struct P6Card: View {
    let onClose: () -> Void
    let onEmail: () -> Void
    let onApple: () -> Void
    let onGoogle: () -> Void
    let onChild: () -> Void
    let errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundColor(.black)
                Spacer()
                Button { Haptics.tap(); onClose() } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "F0EDF1"))
                            .frame(width: 32, height: 32)
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)

            Text("Get Started")
                .font(.system(size: 27, weight: .semibold))
                .foregroundColor(Color(red: 0.192, green: 0.184, blue: 0.196))
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .appearEffect(delay: 0.15)
                .shimmer(delay: 0.7)

            Text("Register for events, subscribe\nto calendars and manage\nevents you're going to.")
                .font(.system(size: 17))
                .foregroundColor(Color(hex: "948F95"))
                .lineSpacing(4)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .appearEffect(delay: 0.25)

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

            // Email button
            Button(action: onEmail) {
                Text("Continue with Email")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 65)
                    .background(
                        RoundedRectangle(cornerRadius: 29)
                            .fill(Color.black.opacity(0.996))
                    )
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .appearEffect(delay: 0.35)

            // Social buttons
            HStack(spacing: 12) {
                P6AppleButton(action: onApple)
                P6GoogleButton(action: onGoogle)
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .appearEffect(delay: 0.45)

            // Child sign-in entry
            Button(action: onChild) {
                Text("Войти как ребёнок")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(Color(hex: "7c4df0"))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .appearEffect(delay: 0.5)

            // Terms
            P6Terms()
                .padding(.horizontal, 20)
                .padding(.top, 6)
                .padding(.bottom, 90)
                .appearEffect(delay: 0.55)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 50)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

// MARK: - Apple Sign In

private struct P6AppleButton: View {
    let action: () -> Void

    private let bg = Color(red: 0.925, green: 0.918, blue: 0.929).opacity(0.996)

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(bg)
                    .frame(height: 60)
                Image(systemName: "apple.logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 22, height: 26)
                    .foregroundColor(.black)
            }
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(PressableButtonStyle())
    }
}

// MARK: - Google Sign In (placeholder)

private struct P6GoogleButton: View {
    let action: () -> Void

    private let bg = Color(red: 0.925, green: 0.918, blue: 0.929).opacity(0.996)

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 28)
                    .fill(bg)
                    .frame(height: 60)
                Image("google")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 28, height: 28)
                    .clipShape(Circle())
            }
        }
        .frame(maxWidth: .infinity)
        .buttonStyle(PressableButtonStyle())
    }
}

/// Proper multicolor Google "G" logo drawn with arcs + crossbar.
private struct P6GoogleLogo: View {
    private let blue   = Color(hex: "4285F4")
    private let red    = Color(hex: "EA4335")
    private let yellow = Color(hex: "FBBC05")
    private let green  = Color(hex: "34A853")

    var body: some View {
        GeometryReader { geo in
            let s = min(geo.size.width, geo.size.height)
            let lw = s * 0.26
            let ring = s - lw
            let style = StrokeStyle(lineWidth: lw, lineCap: .butt)

            ZStack {
                // Four colored arcs (clockwise from just below 3 o'clock).
                ZStack {
                    Circle().trim(from: 0.06, to: 0.28).stroke(green,  style: style)
                    Circle().trim(from: 0.28, to: 0.50).stroke(yellow, style: style)
                    Circle().trim(from: 0.50, to: 0.78).stroke(red,    style: style)
                    Circle().trim(from: 0.78, to: 1.00).stroke(blue,   style: style)
                }
                .frame(width: ring, height: ring)
                .frame(width: s, height: s)

                // Blue crossbar from centre to the right edge.
                Rectangle()
                    .fill(blue)
                    .frame(width: ring / 2 + lw / 2, height: lw)
                    .position(x: s / 2 + ring / 4, y: s / 2)
            }
            .frame(width: s, height: s)
        }
    }
}

// MARK: - Terms text

private struct P6Terms: View {
    private var termsText: AttributedString {
        var str = AttributedString("By selecting Agree and Continue, I agree to reInspire's Terms of Service and acknowledge the Privacy Policy.")
        str.foregroundColor = Color(hex: "4A4A4A")
        str.font = .system(size: 11, weight: .semibold)

        if let range = str.range(of: "Terms of Service") {
            str[range].foregroundColor = Color(hex: "0048E2")
            str[range].underlineStyle = .single
            str[range].link = URL(string: "https://thechallenges.app/terms.html")
        }
        if let range = str.range(of: "Privacy Policy") {
            str[range].foregroundColor = Color(hex: "0048E2")
            str[range].underlineStyle = .single
            str[range].link = URL(string: "https://thechallenges.app/privacy.html")
        }
        return str
    }

    var body: some View {
        Text(termsText)
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .frame(maxWidth: .infinity, alignment: .center)
    }
}

// MARK: - Email Card

private struct P6EmailCard: View {
    var vm: AuthViewModel
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Image(systemName: "sparkle")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundColor(.black)
                Spacer()
                Button { Haptics.tap(); onBack() } label: {
                    ZStack {
                        Circle()
                            .fill(Color(hex: "F0EDF1"))
                            .frame(width: 32, height: 32)
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)

            // Sign In / Sign Up toggle
            HStack(spacing: 0) {
                ForEach(["Sign In", "Sign Up"], id: \.self) { label in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            vm.isSignUp = (label == "Sign Up")
                            vm.errorMessage = nil
                        }
                    } label: {
                        Text(label)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(
                                (vm.isSignUp ? label == "Sign Up" : label == "Sign In")
                                    ? .black : Color(hex: "ABABAB")
                            )
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(
                                (vm.isSignUp ? label == "Sign Up" : label == "Sign In")
                                    ? Color(hex: "F0EDF1") : Color.clear
                            )
                            .cornerRadius(10)
                    }
                    .buttonStyle(.haptic)
                }
            }
            .padding(4)
            .background(Color(hex: "F7F7F7"))
            .cornerRadius(14)
            .padding(.horizontal, 20)
            .padding(.top, 16)

            VStack(spacing: 16) {
                P6InputField(
                    title: "Email",
                    placeholder: "your@email.com",
                    text: Binding(get: { vm.email }, set: { vm.email = $0 }),
                    isSecure: false
                )

                P6InputField(
                    title: "Password",
                    placeholder: "••••••••",
                    text: Binding(get: { vm.password }, set: { vm.password = $0 }),
                    isSecure: true
                )

                if vm.isSignUp {
                    P6InputField(
                        title: "Confirm Password",
                        placeholder: "••••••••",
                        text: Binding(get: { vm.confirmPassword }, set: { vm.confirmPassword = $0 }),
                        isSecure: true
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)

            if let error = vm.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
            }

            Button {
                Task { await vm.submit() }
            } label: {
                Group {
                    if vm.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Continue")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 65)
                .background(
                    RoundedRectangle(cornerRadius: 29)
                        .fill(vm.isValid ? Color.black : Color(hex: "CCCCCC"))
                )
            }
            .buttonStyle(PressableButtonStyle())
            .disabled(!vm.isValid || vm.isLoading)
            .padding(.horizontal, 20)
            .padding(.top, 24)

            P6Terms()
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 48)
        }
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 50)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.08), radius: 20, x: 0, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }
}

// MARK: - Input Field

private struct P6InputField: View {
    let title: String
    let placeholder: String
    @Binding var text: String
    let isSecure: Bool
    @State private var showPassword = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 14))
                .foregroundColor(.black)

            HStack(spacing: 10) {
                if isSecure && !showPassword {
                    SecureField(placeholder, text: $text)
                        .font(.system(size: 16))
                        .frame(maxWidth: .infinity)
                        .textContentType(.password)
                        // Card is a fixed white surface, so force dark text/cursor
                        // -- otherwise in system dark mode the typed text renders
                        // white-on-white and is invisible.
                        .foregroundColor(.black)
                        .tint(Color(hex: "0048E2"))
                } else {
                    TextField(placeholder, text: $text)
                        .font(.system(size: 16))
                        .frame(maxWidth: .infinity)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)
                        .foregroundColor(.black)
                        .tint(Color(hex: "0048E2"))
                }

                if isSecure {
                    Button {
                        Haptics.tap()
                        showPassword.toggle()
                    } label: {
                        Image(systemName: showPassword ? "eye" : "eye.slash")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 20, height: 20)
                            .foregroundColor(.black.opacity(0.4))
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 56)
            .background(Color.white)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color(red: 0.847, green: 0.855, blue: 0.863), lineWidth: 1)
            )
        }
    }
}

#Preview {
    GetStartedScreen(onClose: {})
        .environment(AuthService.shared)
}
