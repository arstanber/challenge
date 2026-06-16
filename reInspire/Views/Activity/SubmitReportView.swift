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
                        result: vm.lastAIResult,
                        stage: vm.submissionStage,
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
            .navigationTitle(showResult ? "" : "Отчёт")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !showResult {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Отмена") { Haptics.tap(); dismiss() }
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
                        Text("Сделать фото")
                            .font(.headline).foregroundStyle(Color(hex: "0048E2"))
                        Text("Нажмите, чтобы открыть камеру")
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
                    Text("ИИ проверит: \(condition)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            TextField("Комментарий (необязательно)", text: $comment, axis: .vertical)
                .lineLimit(2...3)
                .padding(12)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: - Goal section

    private var goalSection: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Отметить прогресс").font(.headline)
                if let target = activity.goalTarget {
                    Text(String(format: "Сейчас: %.0f / %.0f", activity.goalProgress, target))
                        .font(.subheadline).foregroundStyle(.secondary)
                    ProgressView(value: activity.progressFraction).tint(Color(hex: "0048E2"))
                }
            }
            TextField("Значение прогресса (например, 5 для 5 км)", text: $progressValue)
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
            Text("Нажмите ниже, чтобы отметить \(activity.type == .habit ? "привычку" : "задачу") выполненной")
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
                            Text(loadingLabel)
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
                                Text("Проверяем оправдание…")
                            }
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: "bandage")
                                Text("Отправить как оправдание")
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
                Text("Нажмите \"Отправить как оправдание\", если была веская причина (травма, болезнь, форс-мажор)")
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
            // Show the scanning screen immediately so the animation overlaps
            // the upload + verify round-trip instead of following it.
            showResult = true
            await vm.submitPhotoReport(image: image, comment: comment, isExcuse: isExcuse)
            // Hard failure (upload/insert) -- back out to the form with the error.
            if vm.errorMessage != nil { showResult = false }
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
        case .challenge, .assignment: return "Отправить фото"
        case .goal:                   return "Отметить"
        case .task:                   return "Готово"
        case .habit:                  return "Отметиться"
        }
    }

    private var loadingLabel: String {
        switch vm.submissionStage {
        case .uploading: return "Загружаем фото…"
        default:         return "ИИ проверяет…"
        }
    }

    private var isSubmitDisabled: Bool {
        switch activity.type {
        case .challenge, .assignment:
            return capturedImage == nil
        case .goal:
            // Reject empty, non-numeric, and negative values -- a negative
            // progress entry would corrupt goal tracking.
            guard let v = Double(progressValue) else { return true }
            return v < 0
        case .task, .habit:
            return false
        }
    }
}

// MARK: - AI Result Screen

private struct AIVerificationResultScreen: View {
    /// nil while the report is still uploading / verifying.
    let result: AIVerificationResult?
    let stage: ActivityDetailViewModel.SubmissionStage
    let explanation: String?
    let wasExcuse: Bool
    let onDone: () -> Void
    let onRetry: () -> Void

    // The verdict is the emotional payoff of the photo flow. The scanning beat
    // now overlaps the network round-trip (we appear as soon as submit starts),
    // with a short minimum floor so the reveal never feels like a glitch.
    @State private var revealed = false
    @State private var floorElapsed = false
    @State private var scanPulse = false
    @State private var scanSpin = false
    @State private var confettiTrigger = 0
    @State private var bonusXP: Int?

    /// Resolved verdict once revealed; safe fallback while still scanning.
    private var r: AIVerificationResult { result ?? .pending }

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
        .onAppear(perform: startScanning)
        .onChange(of: result) { _, _ in maybeReveal() }
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
            Text(scanText)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var scanText: String {
        if stage == .uploading { return "Загружаем фото…" }
        return wasExcuse ? "ИИ проверяет оправдание…" : "ИИ проверяет фото…"
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
                        Text("Бонус удачи: +\(bonusXP) XP")
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

            if r == .rejected {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(Color(hex: "0048E2"))
                    Text("Если была веская причина, в следующий раз нажмите \"Отправить как оправдание\"")
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
                Text(r == .approved || r == .excused ? "Готово 🎉" : "Закрыть")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity).frame(height: 50)
            }
            .buttonStyle(.borderedProminent)
            .tint(bgColor)

            if r == .rejected {
                Button { Haptics.tap(); onRetry() } label: {
                    Text("Ещё раз")
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

    /// Starts the looping scan animation and a minimum-floor timer. The reveal
    /// then waits for both the verdict to arrive and the floor to elapse.
    private func startScanning() {
        withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
            scanPulse = true
        }
        withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
            scanSpin = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            floorElapsed = true
            maybeReveal()
        }
        maybeReveal()   // result may already be present (e.g. notApplicable)
    }

    private func maybeReveal() {
        guard !revealed, floorElapsed, result != nil else { return }
        withAnimation(.spring(response: 0.4, dampingFraction: 0.6)) {
            revealed = true
        }
        playVerdictFeedback()
        if r == .approved {
            confettiTrigger += 1
            maybeAwardBonus()
        }
    }

    private func playVerdictFeedback() {
        switch r {
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
        switch r {
        case .approved:      return .green
        case .rejected:      return .red
        case .excused:       return .purple
        case .notApplicable: return .orange
        case .pending:       return .orange
        }
    }

    private var iconName: String {
        switch r {
        case .approved:      return "checkmark.seal.fill"
        case .rejected:      return "xmark.seal.fill"
        case .excused:       return "bandage.fill"
        case .notApplicable: return "checkmark.circle.fill"
        case .pending:       return "clock.fill"
        }
    }

    private var title: String {
        switch r {
        case .approved:      return "Задача выполнена! 🔥"
        case .rejected:      return "Не засчитано"
        case .excused:       return wasExcuse ? "Оправдание принято" : "Принято"
        case .notApplicable: return "Отправлено!"
        case .pending:       return "Проверяем…"
        }
    }
}
