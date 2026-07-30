import SwiftUI
import UIKit

// MARK: - Complete-a-task flow (live camera → required-photo prompt → optional AI verify → done)

struct CompleteTaskView: View {
    let activity: Activity
    /// Called only when the task is successfully verified/completed.
    let onCompleted: () -> Void

    @State private var vm: ActivityDetailViewModel
    @StateObject private var camera = CameraModel()
    @Environment(\.dismiss) private var dismiss

    @State private var capturedImage: UIImage?
    @State private var showLibrary = false
    @State private var rejectionReason: String?
    @State private var verdict: VerdictInfo?

    struct VerdictInfo: Identifiable {
        let id = UUID()
        let result: AIVerificationResult
        let explanation: String?
    }

    init(activity: Activity, onCompleted: @escaping () -> Void) {
        self.activity = activity
        self.onCompleted = onCompleted
        _vm = State(initialValue: ActivityDetailViewModel(activity: activity))
    }

    private var requiresAI: Bool { activity.requiresPhotoProof }

    /// What kind of photo the user must take.
    private var requirementLine: String {
        if let c = activity.condition, !c.trimmingCharacters(in: .whitespaces).isEmpty {
            return c
        }
        return String(localized: "Сделай фото, подтверждающее выполнение")
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let image = capturedImage {
                reviewView(image)
            } else {
                cameraView
            }
        }
        .overlay { if let verdict { verdictOverlay(verdict) } }
        .onAppear { if capturedImage == nil { camera.start() } }
        .onDisappear { camera.stop() }
        .onReceive(camera.$captured) { img in
            if let img { capturedImage = img; camera.stop() }
        }
        .fullScreenCover(isPresented: $showLibrary) {
            TaskImagePicker(image: $capturedImage).ignoresSafeArea()
        }
    }

    // MARK: - Camera page

    private var cameraView: some View {
        ZStack {
            if camera.isAvailable {
                CameraPreview(camera: camera).ignoresSafeArea()
            } else if camera.permissionDenied {
                unavailableView(
                    icon: "lock.fill",
                    text: String(localized: "Нет доступа к камере"),
                    primary: String(localized: "Открыть настройки"),
                    action: { if let u = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(u) } }
                )
            } else {
                unavailableView(
                    icon: "camera.fill",
                    text: String(localized: "Камера недоступна"),
                    primary: String(localized: "Выбрать из галереи"),
                    action: { showLibrary = true }
                )
            }

            // Top/bottom scrims
            VStack {
                LinearGradient(colors: [.black.opacity(0.6), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 220)
                Spacer()
                LinearGradient(colors: [.clear, .black.opacity(0.65)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 220)
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                requirementCard
                    .padding(.top, 8)
                Spacer()
                if camera.isAvailable {
                    captureControls.padding(.bottom, 34)
                }
            }
            .padding(.horizontal, 20)
            .readableWidth()

            // Close
            VStack {
                HStack {
                    closeButton
                    Spacer()
                }
                Spacer()
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)
        }
    }

    private var requirementCard: some View {
        VStack(spacing: 6) {
            Text(activity.title)
                .font(.system(size: 18, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            HStack(spacing: 6) {
                Image(systemName: "camera.viewfinder").font(.system(size: 13))
                Text(requirementLine)
                    .font(.system(size: 14, weight: .medium))
                    .multilineTextAlignment(.center)
            }
            .foregroundColor(Color(hex: "FFB23D"))
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.ultraThinMaterial))
    }

    private var captureControls: some View {
        HStack {
            Button { Haptics.tap(); showLibrary = true } label: {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
                    .frame(width: 56, height: 56)
            }
            Spacer()
            Button { Haptics.medium(); camera.capture() } label: {
                ZStack {
                    Circle().strokeBorder(.white, lineWidth: 4).frame(width: 78, height: 78)
                    Circle().fill(.white).frame(width: 62, height: 62)
                }
            }
            Spacer()
            if camera.canSwitchCamera {
                Button {
                    Haptics.tap()
                    camera.switchCamera()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.system(size: 24, weight: .medium))
                        .foregroundColor(.white)
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(.black.opacity(0.35)))
                }
                .accessibilityLabel(String(localized: "Сменить камеру"))
            } else {
                Color.clear.frame(width: 56, height: 56)
            }
        }
        .padding(.horizontal, 24)
    }

    private var closeButton: some View {
        Button { Haptics.tap(); dismiss() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 40, height: 40)
                .background(Circle().fill(.black.opacity(0.4)))
        }
    }

    private func unavailableView(icon: String, text: String, primary: String, action: @escaping () -> Void) -> some View {
        VStack(spacing: 16) {
            Image(systemName: icon).font(.system(size: 44)).foregroundColor(.white.opacity(0.7))
            Text(text).font(.system(size: 18, weight: .semibold)).foregroundColor(.white)
            Button { Haptics.tap(); action() } label: {
                Text(primary)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 22).frame(height: 50)
                    .background(Capsule().fill(.white))
            }
        }
    }

    // MARK: - Review

    private func reviewView(_ image: UIImage) -> some View {
        VStack(spacing: 0) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 20))
                .padding()

            VStack(spacing: 6) {
                Text(activity.title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                Label(requirementLine, systemImage: "camera.viewfinder")
                    .font(.system(size: 13))
                    .foregroundColor(Color(hex: "FFB23D"))
                    .multilineTextAlignment(.center)
                if let reason = rejectionReason {
                    Text(reason)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 24)

            HStack(spacing: 12) {
                Button {
                    Haptics.tap()
                    rejectionReason = nil
                    capturedImage = nil
                    camera.captured = nil
                    camera.start()
                } label: {
                    Text("Переснять")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity).frame(height: 56)
                        .background(Color.white.opacity(0.18))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    Haptics.tap()
                    Task { await submit(image) }
                } label: {
                    Group {
                        if vm.isSubmittingReport {
                            HStack(spacing: 8) {
                                ProgressView().tint(.black)
                                Text(vm.submissionStage == .uploading ? "Загружаем фото…" : "ИИ проверяет…")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.black)
                            }
                        } else {
                            Text(requiresAI ? "Проверить" : "Отправить")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundColor(.black)
                        }
                    }
                    .frame(maxWidth: .infinity).frame(height: 56)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(vm.isSubmittingReport)
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
            .readableWidth(480)
        }
    }

    // MARK: - Submit

    private func submit(_ image: UIImage) async {
        rejectionReason = nil
        await vm.submitPhotoReport(image: image, comment: "")

        if let error = vm.errorMessage {
            rejectionReason = error
            Haptics.error()
            return
        }

        let result = vm.lastAIResult ?? .notApplicable
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            verdict = VerdictInfo(result: result, explanation: vm.lastAIExplanation)
        }
        if result == .approved || result == .excused || result == .notApplicable {
            Haptics.success()
        } else {
            Haptics.error()
        }
    }

    private func verdictOverlay(_ info: VerdictInfo) -> some View {
        VerdictOverlay(
            info: info,
            onPrimary: {
                switch info.result {
                case .approved, .excused, .notApplicable:
                    onCompleted()
                    dismiss()
                case .rejected, .pending:
                    verdict = nil
                    rejectionReason = nil
                    capturedImage = nil
                    camera.captured = nil
                    camera.start()
                }
            },
            onDismiss: { verdict = nil }
        )
        .transition(.opacity)
    }
}

// MARK: - Verdict overlay (AI explanation)

private struct VerdictOverlay: View {
    let info: CompleteTaskView.VerdictInfo
    let onPrimary: () -> Void
    let onDismiss: () -> Void

    private var isSuccess: Bool {
        info.result == .approved || info.result == .excused || info.result == .notApplicable
    }
    private var accent: Color {
        switch info.result {
        case .approved, .notApplicable: return Color(hex: "27AE60")
        case .excused:                  return Color(hex: "9B59B6")
        case .rejected:                 return Color(hex: "FF3B30")
        case .pending:                  return Color(hex: "FF9500")
        }
    }
    private var headline: String {
        switch info.result {
        case .approved:      return String(localized: "Проверено ✅")
        case .excused:       return String(localized: "Отмазка принята 🙏")
        case .notApplicable: return String(localized: "Готово")
        case .rejected:      return String(localized: "Не засчитано")
        case .pending:       return String(localized: "Проверяем…")
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea()
                .onTapGesture { if !isSuccess { Haptics.tap(); onDismiss() } }

            VStack(spacing: 18) {
                ZStack {
                    Circle().fill(accent.opacity(0.15)).frame(width: 84, height: 84)
                    Image(systemName: info.result.icon)
                        .font(.system(size: 40, weight: .bold))
                        .foregroundColor(accent)
                }
                .padding(.top, 4)

                Text(headline)
                    .font(.manrope(.bold, size: 22))
                    .foregroundStyle(.primary)

                if let explanation = info.explanation, !explanation.isEmpty {
                    Text(explanation)
                        .font(.manrope(.regular, size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button { Haptics.tap(); onPrimary() } label: {
                    Text(isSuccess ? "Готово" : "Ещё раз")
                        .font(.manrope(.semiBold, size: 17))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(accent)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.top, 4)
            }
            .padding(24)
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .padding(.horizontal, 32)
            .frame(maxWidth: 480)
        }
    }
}

// MARK: - UIKit library picker (fallback when no camera / simulator)

private struct TaskImagePicker: UIViewControllerRepresentable {
    @Binding var image: UIImage?
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: TaskImagePicker
        init(_ parent: TaskImagePicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { parent.image = img }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
