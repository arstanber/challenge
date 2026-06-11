import SwiftUI

/// Sheet shown before deleting a task -- requires the user to write why
/// they're deleting it. The reason is logged via `ActivitiesViewModel.deleteActivity`.
struct DeleteReasonSheet: View {
    let activityTitle: String
    let onConfirm: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @FocusState private var focused: Bool

    private var trimmedReason: String {
        reason.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                Text("Почему ты удаляешь «\(activityTitle)»?")
                    .font(.headline)

                Text("Это поможет понять, что не сработало, и не повторить это в будущем.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $reason)
                    .focused($focused)
                    .frame(height: 120)
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )

                Spacer()
            }
            .padding(20)
            .navigationTitle("Удаление задачи")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") {
                        Haptics.tap()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Удалить", role: .destructive) {
                        Haptics.warning()
                        onConfirm(trimmedReason)
                        dismiss()
                    }
                    .disabled(trimmedReason.isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { focused = true }
        }
    }
}

#Preview {
    Color.clear
        .sheet(isPresented: .constant(true)) {
            DeleteReasonSheet(activityTitle: "Утренняя пробежка") { _ in }
        }
}
