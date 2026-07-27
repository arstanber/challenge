import SwiftUI

struct CreateActivityView: View {
    @State private var vm = CreateActivityViewModel()
    @Environment(\.dismiss) private var dismiss

    /// When set, this activity is assigned to the given child (parent flow).
    var presetChildId: UUID?
    /// When set, the activity is assigned to every listed child at once
    /// (parent "assign to all kids" flow). Takes precedence over presetChildId.
    var presetChildIds: [UUID]?
    var presetChildName: String?

    var body: some View {
        NavigationStack {
            Form {
                if let name = presetChildName {
                    Section {
                        Label("Задание для \(name)", systemImage: "person.crop.circle.badge.checkmark")
                            .font(.subheadline.bold())
                            .foregroundStyle(.purple)
                    }
                }
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

                if presetChildName == nil && !vm.type.hasAIVerification {
                    Section {
                        Picker("Как отмечать", selection: $vm.completionMode) {
                            ForEach(ActivityCompletionMode.allCases) { mode in
                                Label(mode.displayName, systemImage: mode.icon).tag(mode)
                            }
                        }
                        if vm.completionMode.needsTarget {
                            TextField(
                                vm.completionMode == .timer ? "Минут в день" : "Целевое значение",
                                text: $vm.goalTarget
                            )
                            .keyboardType(.decimalPad)
                            if vm.completionMode == .counter {
                                TextField("Единица: страницы, км, раз", text: $vm.completionUnit)
                            }
                        }
                    } header: {
                        Text("Выполнение")
                    } footer: {
                        Text(completionModeDescription)
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
                                let labels = [String(localized: "Пн"), String(localized: "Вт"), String(localized: "Ср"), String(localized: "Чт"), String(localized: "Пт"), String(localized: "Сб"), String(localized: "Вс")]
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
                    let isAssignment = presetChildName != nil
                    Toggle(isAssignment ? String(localized: "Поставить дедлайн") : "Set deadline", isOn: $vm.hasDeadline)
                    if vm.hasDeadline {
                        DatePicker(isAssignment ? String(localized: "Дедлайн") : "Deadline",
                                   selection: $vm.deadline, in: Date()..., displayedComponents: .date)
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
            .hapticFeedback(.selection, trigger: vm.type)
            .hapticFeedback(.selection, trigger: vm.completionMode)
            .hapticFeedback(.selection, trigger: vm.frequency)
            .hapticFeedback(.selection, trigger: vm.hasDeadline)
            .hapticFeedback(.selection, trigger: vm.reminderEnabled)
            .navigationTitle(presetChildName == nil ? "New activity" : String(localized: "Новое задание"))
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let ids = presetChildIds { vm.assignToChildIds = ids }
                else if let id = presetChildId { vm.assignToChildId = id }
            }
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

    private var completionModeDescription: String {
        switch vm.completionMode {
        case .check: return String(localized: "Обычная отметка одним нажатием.")
        case .counter: return String(localized: "Записывайте числовой прогресс.")
        case .timer: return String(localized: "Засчитывайте время из встроенного таймера.")
        case .abstinence: return String(localized: "Подтверждайте каждый день без нежелательного действия.")
        }
    }
}

#Preview {
    CreateActivityView()
}
