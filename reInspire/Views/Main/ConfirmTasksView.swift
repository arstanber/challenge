import SwiftUI

struct ConfirmTasksView: View {

    let onConfirm: ([GeminiTask]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tasks: [GeminiTask]
    @State private var selected: Set<Int>

    // Schedule voice step
    @State private var scheduleRecognizer = SpeechRecognizer()
    @State private var isParsingSchedule = false
    @State private var scheduleError: String?

    private static let primaryBlue = Color(hex: "4681FF")
    private static let cardAngles: [Double] = [3.0, -2.0, 1.5, -2.8, 2.2, -1.3, 1.8]

    init(tasks: [GeminiTask], onConfirm: @escaping ([GeminiTask]) -> Void) {
        _tasks = State(initialValue: tasks)
        _selected = State(initialValue: Set(tasks.indices))
        self.onConfirm = onConfirm
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                // Nav title
                HStack {
                    Spacer()
                    Text("reInspire.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.black)
                    Spacer()
                }
                .padding(.vertical, 12)

                // Blue card
                ZStack(alignment: .top) {
                    RoundedRectangle(cornerRadius: 50)
                        .fill(Self.primaryBlue)
                        .ignoresSafeArea(edges: .bottom)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("Add these tasks?")
                                .font(.system(size: 36, weight: .bold).italic())
                                .foregroundColor(.white)
                                .padding(.top, 32)
                                .padding(.leading, 20)
                                .padding(.bottom, 28)

                            // Rotated task cards
                            VStack(spacing: 18) {
                                ForEach(tasks.indices, id: \.self) { i in
                                    ConfirmTaskCard(
                                        task: tasks[i],
                                        isChecked: selected.contains(i),
                                        rotation: Self.cardAngles[i % Self.cardAngles.count]
                                    ) {
                                        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
                                            if selected.contains(i) { selected.remove(i) }
                                            else { selected.insert(i) }
                                        }
                                    }
                                    .padding(.horizontal, 20)
                                }
                            }

                            // "When?" voice section
                            scheduleSection
                                .padding(.top, 28)
                                .padding(.horizontal, 20)
                                .padding(.bottom, 110)
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .readableWidth(600)

            // Add tasks button
            VStack {
                Spacer()
                Button {
                    Haptics.tap()
                    let picked = tasks.indices.filter { selected.contains($0) }.map { tasks[$0] }
                    dismiss()
                    onConfirm(picked)
                } label: {
                    Text("Add tasks ✦")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(selected.isEmpty ? Color(hex: "C0C0C0") : Color(hex: "414040"))
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                        .background(Color(hex: "DEDEDE"))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color(hex: "ACACAC"), lineWidth: 1)
                        )
                        .cornerRadius(12)
                }
                .disabled(selected.isEmpty)
                .padding(.horizontal, 15)
                .padding(.bottom, 24)
                .readableWidth(600)
            }
        }
        .onDisappear { scheduleRecognizer.stop() }
    }

    // MARK: - Schedule section

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "clock.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.white.opacity(0.7))
                Text("Когда? (необязательно)")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }

            // Mic + waveform row
            HStack(spacing: 14) {
                Button {
                    toggleScheduleListening()
                } label: {
                    ZStack {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 52, height: 52)
                            .shadow(color: .black.opacity(0.1), radius: 6, x: 0, y: 3)
                        if isParsingSchedule {
                            ProgressView().tint(Self.primaryBlue)
                        } else {
                            Image(systemName: scheduleRecognizer.isListening ? "pause.fill" : "mic.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(scheduleRecognizer.isListening
                                    ? Self.primaryBlue
                                    : Color(hex: "414040"))
                        }
                    }
                }
                .buttonStyle(.haptic)
                .disabled(isParsingSchedule)

                if scheduleRecognizer.isListening {
                    ScheduleWaveform(levels: scheduleRecognizer.levels)
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                } else if !scheduleRecognizer.transcript.isEmpty {
                    Text(scheduleRecognizer.transcript)
                        .font(.system(size: 14))
                        .foregroundColor(.white.opacity(0.9))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(3)
                } else {
                    Text("Скажи напр.: «первое в 7 утра каждый день 2 недели»")
                        .font(.system(size: 13))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)
                }
            }

            if let error = scheduleError {
                Text(error)
                    .font(.system(size: 12))
                    .foregroundColor(.yellow.opacity(0.9))
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.12))
        .cornerRadius(20)
    }

    // MARK: - Actions

    private func toggleScheduleListening() {
        if scheduleRecognizer.isListening {
            Task { await parseSchedule() }
        } else {
            scheduleError = nil
            scheduleRecognizer.reset()
            Task {
                _ = await scheduleRecognizer.requestAuthorization()
                try? scheduleRecognizer.start()
            }
        }
    }

    private func parseSchedule() async {
        let transcript = await scheduleRecognizer.stopAndAwaitFinalTranscript()
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isParsingSchedule = true
        defer { isParsingSchedule = false }

        do {
            let titles = tasks.map(\.title)
            let entries = try await GeminiService.shared.parseSchedule(tasks: titles, transcript: transcript)
            for entry in entries where entry.index < tasks.count {
                tasks[entry.index].scheduleLabel    = entry.scheduleLabel
                tasks[entry.index].durationLabel    = entry.durationLabel
                tasks[entry.index].scheduleFrequency = entry.frequency
                tasks[entry.index].reminderHour     = entry.hour
                tasks[entry.index].reminderMinute   = entry.minute
                tasks[entry.index].deadlineDays     = entry.deadlineDays
            }
            Haptics.success()
        } catch {
            scheduleError = error.localizedDescription
            Haptics.error()
        }
    }
}

// MARK: - Task card with rotation

private struct ConfirmTaskCard: View {
    let task: GeminiTask
    let isChecked: Bool
    let rotation: Double
    let onToggle: () -> Void

    private var categoryColor: Color {
        TaskCategorizer.category(forLabel: task.category).color
    }

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.white)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 74)
                .shadow(color: .black.opacity(0.10), radius: 8, x: 0, y: 3)

            HStack(spacing: 12) {
                Button(action: onToggle) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white)
                            .frame(width: 24, height: 24)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color(hex: "D6D6D6"), lineWidth: 2)
                            )
                        if isChecked {
                            Image(systemName: "checkmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundColor(Color(hex: "4681FF"))
                        }
                    }
                }
                .buttonStyle(.haptic)

                VStack(alignment: .leading, spacing: 6) {
                    Text(task.title)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.black)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        // Category
                        Text(task.category)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(categoryColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(categoryColor.opacity(0.1))
                            .cornerRadius(4)

                        // Schedule (if set)
                        if let schedule = task.scheduleLabel {
                            Text(schedule.uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(Color.black)
                                .cornerRadius(4)
                        }

                        // Duration (if set)
                        if let duration = task.durationLabel {
                            Text(duration.uppercased())
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color(hex: "A9001C"))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(4)
                        }

                        // Type (only when no schedule filled yet)
                        if task.scheduleLabel == nil {
                            let typeLabel = task.type == "habit" ? "HABIT" : task.type == "goal" ? "GOAL" : "TASK"
                            Text(typeLabel)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(Color.black)
                                .cornerRadius(4)
                        }
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
        }
        .rotationEffect(.degrees(rotation))
    }

}

// MARK: - Waveform for schedule mic

private struct ScheduleWaveform: View {
    let levels: [CGFloat]
    var body: some View {
        GeometryReader { geo in
            let count = levels.count
            let spacing: CGFloat = 3
            let barW = max(2, (geo.size.width - spacing * CGFloat(max(count-1, 0))) / CGFloat(max(count, 1)))
            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    RoundedRectangle(cornerRadius: barW / 2)
                        .fill(Color.white.opacity(0.8))
                        .frame(width: barW, height: max(3, level * geo.size.height))
                        .animation(.easeOut(duration: 0.1), value: level)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
    }
}

#Preview {
    ConfirmTasksView(
        tasks: [
            GeminiTask(title: "Run 5km every morning", category: "SPORT", type: "habit"),
            GeminiTask(title: "Read a book", category: "STUDY", type: "goal"),
            GeminiTask(title: "Pay the rent", category: "FINANCE", type: "task"),
        ],
        onConfirm: { _ in }
    )
}
