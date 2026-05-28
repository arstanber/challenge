import SwiftUI
import PhotosUI

struct SubmitReportView: View {
    let activity: Activity
    let onSubmit: () -> Void

    @Bindable var vm: ActivityDetailViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPhoto: PhotosPickerItem?
    @State private var selectedImage: UIImage?
    @State private var comment = ""
    @State private var progressValue = ""
    @State private var showCamera = false

    var body: some View {
        NavigationStack {
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
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }

                    submitButton
                }
                .padding()
            }
            .navigationTitle("Submit report")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showCamera) {
                CameraView(image: $selectedImage)
            }
        }
    }

    private var photoSection: some View {
        VStack(spacing: 12) {
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 240)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(alignment: .topTrailing) {
                        Button { selectedImage = nil } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .padding(8)
                        }
                    }
            } else {
                HStack(spacing: 16) {
                    Button { showCamera = true } label: {
                        VStack(spacing: 8) {
                            Image(systemName: "camera.fill").font(.largeTitle)
                            Text("Take photo").font(.subheadline)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .foregroundStyle(.blue)

                    PhotosPicker(selection: $selectedPhoto, matching: .images) {
                        VStack(spacing: 8) {
                            Image(systemName: "photo.fill").font(.largeTitle)
                            Text("From gallery").font(.subheadline)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 120)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .foregroundStyle(.blue)
                }
            }

            if let condition = activity.condition {
                HStack(spacing: 8) {
                    Image(systemName: "brain").foregroundStyle(.purple)
                    Text("AI will verify: \(condition)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            }

            TextField("Add a comment (optional)", text: $comment, axis: .vertical)
                .lineLimit(2...3)
                .padding(12)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
        }
        .onChange(of: selectedPhoto) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImage = image
                }
            }
        }
    }

    private var goalSection: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Progress").font(.headline)
                if let target = activity.goalTarget {
                    Text(String(format: "Current: %.0f / %.0f", activity.goalProgress, target))
                        .font(.subheadline).foregroundStyle(.secondary)
                    ProgressView(value: activity.progressFraction).tint(.blue)
                }
            }

            TextField("Add progress value", text: $progressValue)
                .keyboardType(.decimalPad)
                .padding(14)
                .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))

            Text("Optional photo proof")
                .font(.subheadline).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity)
                    .frame(height: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            } else {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Label("Select photo", systemImage: "photo")
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
                }
            }
        }
        .onChange(of: selectedPhoto) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self),
                   let image = UIImage(data: data) {
                    selectedImage = image
                }
            }
        }
    }

    private var taskSection: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            Text("Tap below to mark this \(activity.type == .habit ? "habit" : "task") as completed")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 20)
    }

    private var submitButton: some View {
        Button {
            Task {
                switch activity.type {
                case .challenge, .assignment:
                    guard let image = selectedImage else { return }
                    await vm.submitPhotoReport(image: image, comment: comment)
                case .goal:
                    let value = Double(progressValue) ?? 0
                    await vm.submitGoalProgress(value: value, image: selectedImage)
                case .task, .habit:
                    await vm.submitTaskReport()
                }
                if vm.errorMessage == nil { dismiss(); onSubmit() }
            }
        } label: {
            Group {
                if vm.isSubmittingReport {
                    HStack(spacing: 8) {
                        ProgressView().tint(.white)
                        Text("Submitting...")
                    }
                } else {
                    Text(submitLabel).fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
        }
        .buttonStyle(.borderedProminent)
        .tint(.orange)
        .disabled(isSubmitDisabled || vm.isSubmittingReport)
    }

    private var submitLabel: String {
        switch activity.type {
        case .challenge, .assignment: return "Submit photo report"
        case .goal: return "Log progress"
        case .task: return "Mark as done"
        case .habit: return "Check in"
        }
    }

    private var isSubmitDisabled: Bool {
        switch activity.type {
        case .challenge, .assignment: return selectedImage == nil
        case .goal: return progressValue.isEmpty || Double(progressValue) == nil
        case .task, .habit: return false
        }
    }
}
