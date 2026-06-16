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

                connectorSection

                if vm.showGoalTarget {
                    Section("Цель") {
                        HStack {
                            TextField("Например: 10", text: $vm.goalTarget)
                                .keyboardType(.decimalPad)
                            if let unit = vm.goalTargetUnit {
                                Text(unit).foregroundStyle(.secondary)
                            }
                        }
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
            .hapticFeedback(.selection, trigger: vm.type)
            .hapticFeedback(.selection, trigger: vm.frequency)
            .hapticFeedback(.selection, trigger: vm.hasDeadline)
            .hapticFeedback(.selection, trigger: vm.reminderEnabled)
            .navigationTitle(presetChildName == nil ? "New activity" : "Новое задание")
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

    // MARK: - Connector capability picker

    /// Whether this is a parent assigning to a child. Auto-tracking reads the
    /// current device's connected sources, so it's hidden in that flow.
    private var isChildAssignment: Bool {
        presetChildId != nil || !(presetChildIds?.isEmpty ?? true)
    }

    @ViewBuilder
    private var connectorSection: some View {
        if !isChildAssignment {
            Section {
                if let cap = vm.selectedCapability {
                    selectedCapabilityRow(cap)
                } else {
                    TextField("Например: Chess.com", text: $vm.connectorQuery)
                    ForEach(vm.capabilityResults) { cap in
                        Button { Haptics.selection(); vm.selectCapability(cap) } label: {
                            capabilityRow(cap)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } header: {
                Text("Автопроверка через источник")
            } footer: {
                Text("Введи название источника -- например Chess.com -- и выбери, что засчитывать. Прогресс будет считаться автоматически, без фото.")
            }
        }
    }

    private func capabilityRow(_ cap: ConnectorCapability) -> some View {
        HStack(spacing: 12) {
            connectorIcon(cap.connector)
            VStack(alignment: .leading, spacing: 2) {
                Text(cap.connector.displayName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.primary)
                Text(cap.title)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(cap.connector.tint)
        }
        .contentShape(Rectangle())
    }

    private func selectedCapabilityRow(_ cap: ConnectorCapability) -> some View {
        HStack(spacing: 12) {
            connectorIcon(cap.connector)
            VStack(alignment: .leading, spacing: 2) {
                Text(cap.connector.displayName)
                    .font(.system(size: 16, weight: .medium))
                Text(cap.title)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button {
                Haptics.tap()
                vm.clearCapability()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func connectorIcon(_ connector: DataConnector) -> some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(connector.tint.opacity(0.15))
            .frame(width: 36, height: 36)
            .overlay {
                Image(systemName: connector.icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(connector.tint)
            }
    }
}

#Preview {
    CreateActivityView()
}
