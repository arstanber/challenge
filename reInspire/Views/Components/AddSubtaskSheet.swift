import SwiftUI

// MARK: - Add subtask sheet
// Creates a one-off subtask under a goal parent. Rendering, completion, and
// parent auto-complete are already handled by HomeView / the task engine.

struct AddSubtaskSheet: View {
    let parent: Activity
    var vm: ActivitiesViewModel
    var onCreated: () -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var deadlineOn = false
    @State private var deadline = Calendar.current.date(byAdding: .day, value: 1, to: .now) ?? .now
    @State private var creating = false
    @FocusState private var titleFocused: Bool

    private var canCreate: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !creating
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Подзадача для")
                            .font(.manrope(.medium, size: 13))
                            .foregroundStyle(.secondary)
                        Text(parent.title)
                            .font(.manrope(.semiBold, size: 17))
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    TextField("", text: $title,
                              prompt: Text("Название подзадачи").foregroundColor(.secondary))
                        .font(.manrope(.medium, size: 17))
                        .focused($titleFocused)
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))

                    Toggle(isOn: $deadlineOn.animation(.spring(response: 0.3, dampingFraction: 0.85))) {
                        Text("Срок").font(.manrope(.medium, size: 16))
                    }
                    .padding(.horizontal, 4)

                    if deadlineOn {
                        DatePicker("Дата", selection: $deadline, displayedComponents: .date)
                            .font(.manrope(.medium, size: 16))
                            .padding(.horizontal, 4)
                    }

                    Spacer(minLength: 0)
                }
                .padding(18)
                .readableWidth(520)
            }
            .navigationTitle("Новая подзадача")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { Haptics.tap(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Создать") { create() }
                        .font(.manrope(.semiBold, size: 16))
                        .disabled(!canCreate)
                }
            }
            .onAppear { titleFocused = true }
        }
    }

    private func create() {
        guard canCreate else { return }
        creating = true
        Haptics.success()
        let name = title.trimmingCharacters(in: .whitespaces)
        Task {
            await vm.createSubtask(parent: parent, title: name, deadline: deadlineOn ? deadline : nil)
            onCreated()
            dismiss()
        }
    }
}
