import SwiftUI

struct CreateActivityView: View {
    @State private var vm = CreateActivityViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Activity") {
                    Picker("Type", selection: $vm.type) {
                        ForEach(ActivityType.allCases) { type in
                            Label(type.displayName, systemImage: type.icon).tag(type)
                        }
                    }
                    TextField("Title", text: $vm.title)
                    TextField("Description (optional)", text: $vm.description, axis: .vertical)
                        .lineLimit(2...4)
                }

                if vm.showConditionField {
                    Section {
                        TextField("e.g. Photo at gym with equipment visible", text: $vm.condition, axis: .vertical)
                            .lineLimit(2...4)
                    } header: {
                        Text("AI verification condition")
                    } footer: {
                        Text("Describe what the photo should show. Claude AI will verify each submission.")
                    }
                }

                if vm.showGoalTarget {
                    Section("Goal target") {
                        TextField("Target value (e.g. 100 for 100 km)", text: $vm.goalTarget)
                            .keyboardType(.decimalPad)
                    }
                }

                Section("Schedule") {
                    // .custom is deprecated -- weekly + day picker covers it.
                    Picker("Frequency", selection: $vm.frequency) {
                        ForEach(ActivityFrequency.allCases.filter { $0 != .custom }) { freq in
                            Text(freq.displayName).tag(freq)
                        }
                    }
                    if vm.frequency == .weekly {
                        HStack(spacing: 8) {
                            ForEach(1...7, id: \.self) { day in
                                let labels = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
                                let on = vm.scheduleDays.contains(day)
                                Button {
                                    Haptics.selection()
                                    if on { vm.scheduleDays.remove(day) } else { vm.scheduleDays.insert(day) }
                                } label: {
                                    Text(labels[day - 1])
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundColor(on ? .white : .primary.opacity(0.6))
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 36)
                                        .background(Circle().fill(on ? Color.accentColor : Color.accentColor.opacity(0.12)))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    Toggle("Set deadline", isOn: $vm.hasDeadline)
                    if vm.hasDeadline {
                        DatePicker("Deadline", selection: $vm.deadline, in: Date()..., displayedComponents: .date)
                    }
                    Toggle("Daily reminder", isOn: $vm.reminderEnabled)
                    if vm.reminderEnabled {
                        DatePicker("Reminder time", selection: $vm.reminderTime, displayedComponents: .hourAndMinute)
                    }
                }

                if let error = vm.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: vm.type)
            .sensoryFeedback(.selection, trigger: vm.frequency)
            .sensoryFeedback(.selection, trigger: vm.hasDeadline)
            .sensoryFeedback(.selection, trigger: vm.reminderEnabled)
            .navigationTitle("New activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { Haptics.tap(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        Task {
                            await vm.create()
                            if vm.didCreate { Haptics.success(); dismiss() }
                        }
                    }
                    .fontWeight(.semibold)
                    .disabled(!vm.isValid || vm.isLoading)
                    .overlay {
                        if vm.isLoading { ProgressView().scaleEffect(0.7) }
                    }
                }
            }
        }
    }
}

#Preview {
    CreateActivityView()
}
