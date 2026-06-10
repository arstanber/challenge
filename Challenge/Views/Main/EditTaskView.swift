import SwiftUI

struct EditTaskView: View {
    let activity: Activity
    let onSave: (_ title: String, _ frequency: ActivityFrequency, _ deadline: Date?, _ reminderTime: Date?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var frequency: ActivityFrequency
    @State private var hasDeadline: Bool
    @State private var deadline: Date
    @State private var reminderEnabled: Bool
    @State private var reminderTime: Date

    private let blue = Color(red: 0.0, green: 0.282, blue: 0.886)

    init(activity: Activity,
         onSave: @escaping (String, ActivityFrequency, Date?, Date?) -> Void) {
        self.activity = activity
        self.onSave = onSave
        _title = State(initialValue: activity.title)
        _frequency = State(initialValue: activity.frequency)
        _hasDeadline = State(initialValue: activity.deadline != nil)
        _deadline = State(initialValue: activity.deadline ?? Date())
        _reminderEnabled = State(initialValue: activity.reminderTime != nil)
        _reminderTime = State(initialValue: activity.reminderTime ?? {
            var c = Calendar.current.dateComponents([.year, .month, .day], from: Date())
            c.hour = 9; c.minute = 0
            return Calendar.current.date(from: c) ?? Date()
        }())
    }

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Title") {
                    TextField("Task title", text: $title, axis: .vertical)
                        .font(.manrope(.medium, size: 17))
                }

                Section("Repeat") {
                    Picker("Frequency", selection: $frequency) {
                        Text("One-time").tag(ActivityFrequency.once)
                        Text("Daily").tag(ActivityFrequency.daily)
                        Text("Weekly").tag(ActivityFrequency.weekly)
                    }
                    .pickerStyle(.segmented)
                }

                Section("Deadline") {
                    Toggle("Has deadline", isOn: $hasDeadline.animation())
                        .tint(blue)
                    if hasDeadline {
                        DatePicker("Date", selection: $deadline, displayedComponents: .date)
                    }
                }

                Section("Reminder") {
                    Toggle("Remind me", isOn: $reminderEnabled.animation())
                        .tint(blue)
                    if reminderEnabled {
                        DatePicker("Time", selection: $reminderTime, displayedComponents: .hourAndMinute)
                    }
                }
            }
            .sensoryFeedback(.selection, trigger: frequency)
            .sensoryFeedback(.selection, trigger: hasDeadline)
            .sensoryFeedback(.selection, trigger: reminderEnabled)
            .navigationTitle("Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { Haptics.tap(); dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Haptics.success()
                        onSave(
                            title,
                            frequency,
                            hasDeadline ? deadline : nil,
                            reminderEnabled ? reminderTime : nil
                        )
                        dismiss()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }
}
