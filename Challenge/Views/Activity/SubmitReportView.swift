import SwiftUI

struct SubmitReportView: View {
    let activity: Activity
    let onSubmit: () -> Void

    @Bindable var vm: ActivityDetailViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var capturedImage: UIImage?
    @State private var comment = ""
    @State private var progressValue = ""
    @State private var showCamera = false
    @State private var showResult = false
    @State private var submittedAsExcuse = false

    var body: some View {
        NavigationStack {
            Group {
                if showResult {
                    AIVerificationResultScreen(
                        result: vm.lastAIResult ?? .notApplicable,
                        explanation: vm.lastAIExplanation,
                        wasExcuse: submittedAsExcuse,
                        onDone: { dismiss(); onSubmit() },
                        onRetry: {
                            showResult = false
                            capturedImage = nil
                            comment = ""
                            submittedAsExcuse = false
                        }
                    )
                } else {
                    formContent
                }
            }
            .navigationTitle(showResult ? "" : "Submit report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !showResult {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { Haptics.tap(); dismiss() }
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraView(image: $capturedImage)
            }
        }
    }

    // MARK: - Form

    private var formContent: some View {
        ScrollView {
            VStack(spacing: 20) {
                switch activity.type {
                case .challenge, .assignment:
                    photoSection
                case .goal:
                    goalSection
                case .task, .habit:
                    taskSection
                }

                if let error = vm.errorMessage {
                    Text(error)
                        .font(.caption).foregroundStyle(.red)
                        .multilineTextAlignment(.center).padding(.horizontal)
                }

                submitButtons
            }
            .padding()
            .readableWidth()
        }
    }

    // MARK: - Photo section (camera only)

    private var photoSection: some View {
        VStack(spacing: 14) {
            if let image = capturedImage {
                ZStack(alignment: .topTrailing) {
                    Image(uiImage: image)
                        .resizable().scaledToFill()
                        .frame(maxWidth: .infinity).frame(height: 260)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    Button { Haptics.tap(); capturedImage = nil } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2).foregroundStyle(.white)
                            .shadow(radius: 4).padding(10)
                    }
                }
            } else {
                Button { showCamera = true } label: {
                    VStack(spacing: 12) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(Color(hex: "0048E2"))
                        Text("Take a photo")
                            .font(.headline).foregroundStyle(Color(hex: "0048E2"))
                        Text("Tap to open camera")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).frame(height: 200)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.haptic)
            }

            if let condition = activity.condition {
                HStack(spacing: 8) {
                    Image(systemName: "brain").foregroundStyle(.purple)
                    Text("AI will verify: \(condition)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            TextField("Add a comment (optional)", text: $comment, axis: .vertical)
                .lineLimit(2...3)
                .padding(12)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Goal section

    private var goalSection: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Log progress").font(.headline)
                if let target = activity.goalTarget {
                    Text(String(format: "Current: %.0f / %.0f", activity.goalProgress, target))
                        .font(.subheadline).foregroundStyle(.secondary)
                    ProgressView(value: activity.progressFraction).tint(Color(hex: "0048E2"))
                }
            }
            TextField("Add progress value (e.g. 5 for 5 km)", text: $progressValue)
                .keyboardType(.decimalPad)
                .padding(14)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Task / Habit section

    private var taskSection: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60)).foregroundStyle(.green)
            Text("Tap below to mark this \(activity.type == .habit ? "habit" : "task") as completed")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 20)
    }

    // MARK: - Buttons

    private var submitButtons: some View {
        VStack(spacing: 10) {
            // Primary submit button
            Button {
                Haptics.tap()
                Task { await handleSubmit(isExcuse: false) }
            } label: {
                Group {
                    if vm.isSubmittingReport && !submittedAsExcuse {
                        HStack(spacing: 8) {
                            ProgressView().tint(.white)
                            Text("Verifying with AI…")
                        }
                    } else {
                        Text(submitLabel).fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity).frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .disabled(isSubmitDisabled || vm.isSubmittingReport)

            // Excuse button — only for AI-verified activities
            if activity.type.hasAIVerification && capturedImage != nil {
                Button {
                    Task { await handleSubmit(isExcuse: true) }
                } label: {
                    Group {
                        if vm.isSubmittingReport && submittedAsExcuse {
                            HStack(spacing: 8) {
                                ProgressView().tint(.purple)
                                Text("Checking excuse…")
                            }
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "bandage")
                                Text("Submit as excuse")
                            }
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 44)
                    .foregroundStyle(.purple)
                    .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.purple.opacity(0.4), lineWidth: 1))
                }
                .buttonStyle(.haptic)
                .disabled(vm.isSubmittingReport)
            }

            if activity.type.hasAIVerification {
                Text("\"Submit as excuse\" if you had a valid reason (injury, illness, emergency)")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    // MARK: - Helpers

    private func handleSubmit(isExcuse: Bool) async {
        submittedAsExcuse = isExcuse
        switch activity.type {
        case .challenge, .assignment:
            guard let image = capturedImage else { return }
            await vm.submitPhotoReport(image: image, comment: comment, isExcuse: isExcuse)
            if vm.errorMessage == nil { showResult = true }
        case .goal:
            let value = Double(progressValue) ?? 0
            await vm.submitGoalProgress(value: value, image: nil)
            if vm.errorMessage == nil { dismiss(); onSubmit() }
        case .task, .habit:
            await vm.submitTaskReport()
            if vm.errorMessage == nil { dismiss(); onSubmit() }
        }
    }

    private var submitLabel: String {
        switch activity.type {
        case .challenge, .assignment: return "Submit photo"
        case .goal:                   return "Log progress"
        case .task:                   return "Mark as done"
        case .habit:                  return "Check in"
        }
    }

    private var isSubmitDisabled: Bool {
        switch activity.type {
        case .challenge, .assignment:
            return capturedImage == nil
        case .goal:
            return progressValue.isEmpty || Double(progressValue) == nil
        case .task, .habit:
            return false
        }
    }
}

// MARK: - AI Result Screen

private struct AIVerificationResultScreen: View {
    let result: AIVerificationResult
    let explanation: String?
    let wasExcuse: Bool
    let onDone: () -> Void
    let onRetry: () -> Void

    // The verdict is the emotional payoff of the photo flow, so AI results
    // hide behind a short scanning beat before snapping in with a spring.
    @State private var revealed = false
    @State private var scanPulse = false
    @State private var scanSpin = false
    @State private var confettiTrigger = 0
    @State private var bonusXP: Int?

    /// Only real AI verdicts earn the suspense beat; plain check-ins and
    /// still-pending results reveal immediately.
    private var hasSuspense: Bool {
        switch result {
        case .approved, .rejected, .excused: return true
        case .notApplicable, .pending:       return false
        }
    }

    var body: some View {
        ZStack {
            VStack(spacing: 32) {
                Spacer()

                if revealed {
                    verdictContent
                        .transition(.scale(scale: 0.5).combined(with: .opacity))
                } else {
                    scanningContent
                }

                Spacer()

                if revealed {
                    actionButtons
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            ConfettiView(trigger: confettiTrigger)
                .ignoresSafeArea()
                .allowsHitTesting(false)
        }
        .onAppear(perform: runReveal)
    }

    // MARK: Scanning beat

    private var scanningContent: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .stroke(Color.purple.opacity(0.15), lineWidth: 6)
                    .frame(width: 120, height: 120)
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(Color.purple, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(scanSpin ? 360 : 0))
                Image(systemName: "brain")
                    .font(.system(size: 44))
                    .foregroundStyle(.purple)
                    .scaleEffect(scanPulse ? 1.1 : 0.92)
            }
            Text(wasExcuse ? "AI is checking your excuse…" : "AI is checking your photo…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: Verdict

    private var verdictContent: some View {
        VStack(spacing: 32) {
            ZStack {
                Circle()
                    .fill(bgColor.opacity(0.15))
                    .frame(width: 120, height: 120)
                Image(systemName: iconName)
                    .font(.system(size: 52))
                    .foregroundStyle(bgColor)
            }

            VStack(spacing: 12) {
                Text(title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                if let bonusXP {
                    HStack(spacing: 6) {
                        Text("🎁")
                        Text("Lucky bonus: +\(bonusXP) XP")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.yellow.opacity(0.18), in: Capsule())
                    .transition(.scale(scale: 0.3).combined(with: .opacity))
                }

                if let explanation {
                    Text(explanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }

            if result == .rejected {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(Color(hex: "0048E2"))
                    Text("If you had a valid reason, next time tap \"Submit as excuse\"")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
                .background(Color(hex: "0048E2").opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
            }
        }
    }

    private var actionButtons: some View {
        VStack(spacing: 10) {
            Button { Haptics.tap(); onDone() } label: {
                Text(result == .approved || result == .excused ? "Done 🎉" : "Close")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity).frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(bgColor)

            if result == .rejected {
                Button { Haptics.tap(); onRetry() } label: {
                    Text("Try again")
                        .frame(maxWidth: .infinity).frame(height: 44)
                }
                .buttonStyle(.bordered)
                .tint(.secondary)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }

    // MARK: Reveal choreography

    private func runReveal() {
        guard hasSuspense else {
            revealed = true
            playVerdictFeedback()
            return
        }
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
            scanPulse = true
        }
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
            scanSpin = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
                revealed = true
            }
            playVerdictFeedback()
            if result == .approved {
                confettiTrigger += 1
                maybeAwardBonus()
            }
        }
    }

    private func playVerdictFeedback() {
        switch result {
        case .approved, .excused, .notApplicable: Haptics.success()
        case .rejected:                            Haptics.error()
        case .pending:                             Haptics.warning()
        }
    }

    /// Variable reward: roughly one approved report in five lands a surprise
    /// XP drop. The unpredictability is the point -- do not make it constant.
    private func maybeAwardBonus() {
        guard Int.random(in: 0..<5) == 0 else { return }
        let amount = [15, 15, 25, 25, 50].randomElement()! // non-empty literal
        GamificationEngine.shared.awardBonusXP(amount)
        AnalyticsService.shared.track(.bonusXPDropped, ["amount": amount])
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.55)) {
                bonusXP = amount
            }
        }
    }

    private var bgColor: Color {
        switch result {
        case .approved:      return .green
        case .rejected:      return .red
        case .excused:       return .purple
        case .notApplicable: return .orange
        case .pending:       return .orange
        }
    }

    private var iconName: String {
        switch result {
        case .approved:      return "checkmark.seal.fill"
        case .rejected:      return "xmark.seal.fill"
        case .excused:       return "bandage.fill"
        case .notApplicable: return "checkmark.circle.fill"
        case .pending:       return "clock.fill"
        }
    }

    private var title: String {
        switch result {
        case .approved:      return "Task completed! 🔥"
        case .rejected:      return "Not approved"
        case .excused:       return wasExcuse ? "Excuse accepted" : "Accepted"
        case .notApplicable: return "Submitted!"
        case .pending:       return "Checking…"
        }
    }
}
