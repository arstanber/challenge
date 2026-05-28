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
                        Button("Cancel") { dismiss() }
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
                    Button { capturedImage = nil } label: {
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
                            .foregroundStyle(.blue)
                        Text("Take a photo")
                            .font(.headline).foregroundStyle(.blue)
                        Text("Tap to open camera")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity).frame(height: 200)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)
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
                    ProgressView(value: activity.progressFraction).tint(.blue)
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
                .buttonStyle(.plain)
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

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(bgColor.opacity(0.15))
                    .frame(width: 120, height: 120)
                Image(systemName: iconName)
                    .font(.system(size: 52))
                    .foregroundStyle(bgColor)
            }

            // Title + explanation
            VStack(spacing: 12) {
                Text(title)
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)

                if let explanation {
                    Text(explanation)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
            }

            // Contextual tip
            if result == .rejected {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(.blue)
                    Text("If you had a valid reason, next time tap \"Submit as excuse\"")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
            }

            Spacer()

            // Action buttons
            VStack(spacing: 10) {
                Button(action: onDone) {
                    Text(result == .approved || result == .excused ? "Done 🎉" : "Close")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity).frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(bgColor)

                if result == .rejected {
                    Button(action: onRetry) {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
