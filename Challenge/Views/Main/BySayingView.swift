import SwiftUI

// MARK: - Constants

private enum BSColors {
    static let cardBackground = Color(hex: "F5F5F5")
    static let buttonBlue = Color(hex: "0048E2")
    static let buttonBorder = Color(hex: "ACACAC")
    static let placeholderGray = Color(hex: "BDBDBD")
    static let subtitle = Color(red: 0.416, green: 0.408, blue: 0.408)
    static let micActive = Color(red: 0.0, green: 0.282, blue: 0.886)
    static let waveformPrimary = Color(red: 0.0, green: 0.282, blue: 0.886)
    static let waveformSecondary = Color(red: 0.474, green: 0.641, blue: 1.0)
    static let controlBg = Color(red: 0.970, green: 0.970, blue: 0.970)
    static let checkboxBorder = Color(red: 0.839, green: 0.839, blue: 0.839)
}

private enum BSPhase { case idle, listening }

// MARK: - Main view

struct BySayingView: View {

    var workspaceId: UUID? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var recognizer = SpeechRecognizer()
    @State private var phase: BSPhase = .idle
    @State private var isSaving = false
    @State private var isAnalyzing = false
    @State private var selectedLanguage = "RU"
    @State private var geminiTasks: [GeminiTask] = []
    @State private var showConfirmation = false
    @State private var analyzeError: String?

    // Live heuristic preview while the user is still speaking.
    private var heuristicTasks: [(title: String, category: TaskCategory)] {
        BySayingParser.tasks(from: recognizer.transcript)
            .map { ($0, TaskCategorizer.category(for: $0)) }
    }

    // Show Gemini output once available, otherwise live heuristic cards.
    private var displayTasks: [(title: String, category: TaskCategory)] {
        geminiTasks.isEmpty
            ? heuristicTasks
            : geminiTasks.map { ($0.title, TaskCategorizer.category(forLabel: $0.category)) }
    }

    private var hasTasks: Bool { !displayTasks.isEmpty }

    private var selectedLocale: Locale {
        selectedLanguage == "RU" ? Locale(identifier: "ru-RU") : Locale(identifier: "en-US")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.white.ignoresSafeArea()
                VStack(spacing: 0) {
                    Text("The Challenge.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.top, 16)
                        .padding(.bottom, 8)

                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 50)
                            .fill(BSColors.cardBackground)
                            .ignoresSafeArea(edges: .bottom)
                        switch phase {
                        case .idle:      idleContent
                        case .listening: listeningContent
                        }
                    }
                    .padding(.horizontal, 15)
                    .padding(.vertical, 12)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { Haptics.tap(); recognizer.stop(); dismiss() }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .onDisappear { recognizer.stop() }
            .fullScreenCover(isPresented: $showConfirmation) {
                ConfirmTasksView(tasks: geminiTasks) { picked in
                    Task { await saveTasks(picked) }
                }
            }
        }
    }

    // MARK: - Idle

    private var idleContent: some View {
        VStack {
            Spacer()
            VStack(spacing: 16) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 140, height: 140)
                        .overlay(Circle().stroke(Color.gray.opacity(0.2), lineWidth: 2))
                    Image(systemName: "mic.fill")
                        .font(.system(size: 48, weight: .medium))
                        .foregroundColor(.black.opacity(0.4))
                }
                Text("Tap the button to start")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(BSColors.placeholderGray)
            }
            Spacer()

            if let error = recognizer.errorMessage {
                Text(error)
                    .font(.system(size: 13))
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
            }

            // Language picker
            HStack(spacing: 0) {
                ForEach(["RU", "EN"], id: \.self) { lang in
                    Button {
                        Haptics.selection()
                        selectedLanguage = lang
                    } label: {
                        Text(lang)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(selectedLanguage == lang ? .white : Color.gray)
                            .frame(width: 48, height: 30)
                            .background(selectedLanguage == lang ? BSColors.buttonBlue : Color.clear)
                            .cornerRadius(7)
                    }
                }
            }
            .padding(3)
            .background(Color.black.opacity(0.06))
            .cornerRadius(10)
            .padding(.bottom, 14)

            Button {
                Task { await startListening() }
            } label: {
                HStack(spacing: 8) {
                    Text("Start Speaking")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(.white)
                    Image(systemName: "sparkle")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 60)
                .background(BSColors.buttonBlue)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(BSColors.buttonBorder, lineWidth: 1))
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.horizontal, 22)
            .padding(.bottom, 22)
        }
    }

    // MARK: - Listening

    private var listeningContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(Color.white)
                        .frame(width: 40, height: 40)
                        .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(BSColors.micActive)
                }
                Text("By saying")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.black)
                Spacer()
                // Language badge (read-only while listening)
                Text(selectedLanguage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(BSColors.micActive)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(BSColors.micActive.opacity(0.1))
                    .cornerRadius(6)
            }
            .padding(.top, 28)
            .padding(.horizontal, 28)

            ScrollView {
                VStack(spacing: 14) {
                    ForEach(Array(displayTasks.enumerated()), id: \.offset) { _, item in
                        BSTaskCard(title: item.title, category: item.category)
                    }
                    if isAnalyzing {
                        HStack(spacing: 10) {
                            ProgressView().tint(BSColors.micActive)
                            Text("Analyzing with AI…")
                                .font(.system(size: 14))
                                .foregroundColor(BSColors.subtitle)
                        }
                        .padding(.top, 8)
                    }
                }
                .padding(.top, 20)
                .padding(.horizontal, 28)
                .animation(.easeInOut(duration: 0.25), value: displayTasks.map(\.title))
            }

            Spacer(minLength: 0)

            VStack(spacing: 6) {
                Text(recognizer.isListening ? "Listening…" : (isAnalyzing ? "AI is thinking…" : "Paused"))
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.black)
                Text("Speak everything you need to do")
                    .font(.system(size: 16))
                    .foregroundColor(BSColors.subtitle)

                if let error = analyzeError {
                    Text(error)
                        .font(.system(size: 12))
                        .foregroundColor(.red.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .padding(.top, 2)
                }

                HStack(spacing: 16) {
                    // Pause / Resume button
                    Button {
                        togglePause()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(BSColors.controlBg)
                                .frame(width: 56, height: 56)
                                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                            if isAnalyzing {
                                ProgressView().tint(.black)
                            } else {
                                Image(systemName: recognizer.isListening ? "pause.fill" : "mic.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(.black)
                            }
                        }
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(isAnalyzing)

                    BSWaveform(levels: recognizer.levels)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)

                    // Confirm button
                    Button {
                        Task { await confirm() }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(hasTasks ? BSColors.buttonBlue : BSColors.controlBg)
                                .frame(width: 56, height: 56)
                                .shadow(color: .black.opacity(0.08), radius: 6, x: 0, y: 3)
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(hasTasks ? .white : .black)
                            }
                        }
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(!hasTasks || isSaving || isAnalyzing)
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
            }
            .padding(.bottom, 36)
        }
    }

    // MARK: - Actions

    private func startListening() async {
        recognizer.errorMessage = nil
        recognizer.setLocale(selectedLocale)
        let ok = await recognizer.requestAuthorization()
        guard ok else { return }
        do {
            recognizer.reset()
            geminiTasks = []
            try recognizer.start()
            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { phase = .listening }
        } catch {
            recognizer.errorMessage = error.localizedDescription
        }
    }

    private func togglePause() {
        if recognizer.isListening {
            Task { await pauseAndAnalyze() }
        } else {
            // Resume: clear Gemini output so live heuristic shows again.
            geminiTasks = []
            analyzeError = nil
            recognizer.reset()
            try? recognizer.start()
        }
    }

    /// Stop STT, wait for the final Apple transcript, ask Gemini to clean it,
    /// fall back to the local heuristic if Gemini fails, then open confirmation.
    private func pauseAndAnalyze() async {
        analyzeError = nil
        let finalTranscript = await recognizer.stopAndAwaitFinalTranscript()
        guard !finalTranscript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            analyzeError = "Didn't catch anything — try again"
            Haptics.error()
            return
        }

        isAnalyzing = true
        defer { isAnalyzing = false }

        do {
            let tasks = try await GeminiService.shared.parseTasks(from: finalTranscript)
            geminiTasks = tasks.isEmpty ? heuristicToGemini() : tasks
        } catch {
            // Gemini unavailable — fall back to local parser so user can still save.
            analyzeError = "AI unavailable, using smart parsing"
            geminiTasks = heuristicToGemini()
        }

        if !geminiTasks.isEmpty {
            showConfirmation = true
        }
    }

    private func confirm() async {
        if recognizer.isListening || geminiTasks.isEmpty {
            await pauseAndAnalyze()
        } else {
            showConfirmation = true
        }
    }

    /// Convert the local heuristic result into [GeminiTask] as a Gemini fallback.
    private func heuristicToGemini() -> [GeminiTask] {
        BySayingParser.tasks(from: recognizer.transcript).map { title in
            let cat = TaskCategorizer.category(for: title)
            let typeStr: String
            switch TaskCategorizer.activityType(for: cat) {
            case .habit: typeStr = "habit"
            case .goal:  typeStr = "goal"
            default:     typeStr = "task"
            }
            return GeminiTask(title: title, category: cat.label, type: typeStr)
        }
    }

    private func saveTasks(_ tasks: [GeminiTask]) async {
        guard !tasks.isEmpty else { dismiss(); return }
        isSaving = true
        for task in tasks {
            let vm = CreateActivityViewModel()
            vm.title = task.title
            vm.type = activityType(from: task.type, category: task.category)
            vm.workspaceId = workspaceId
            vm.category = task.category

            switch task.scheduleFrequency {
            case "daily":  vm.frequency = .daily
            case "weekly": vm.frequency = .weekly
            default:       vm.frequency = .once
            }

            if let days = task.deadlineDays, days > 0 {
                vm.hasDeadline = true
                vm.deadline = Calendar.current.date(byAdding: .day, value: days, to: Date()) ?? vm.deadline
            } else {
                vm.hasDeadline = false
            }

            if let hour = task.reminderHour {
                vm.reminderEnabled = true
                var comps = Calendar.current.dateComponents([.year, .month, .day], from: Date())
                comps.hour = hour
                comps.minute = task.reminderMinute ?? 0
                vm.reminderTime = Calendar.current.date(from: comps) ?? vm.reminderTime
            } else {
                vm.reminderEnabled = false
            }

            await vm.create()
        }
        isSaving = false
        Haptics.success()
        dismiss()
    }

    private func activityType(from type: String, category: String) -> ActivityType {
        switch type {
        case "habit": return .habit
        case "goal":  return .goal
        default:      return TaskCategorizer.activityType(for: TaskCategorizer.category(forLabel: category))
        }
    }
}

// MARK: - Task card

private struct BSTaskCard: View {
    let title: String
    let category: TaskCategory
    @State private var isChecked = false

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.white)
                .frame(height: 74)
                .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)

            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isChecked ? BSColors.micActive : Color.white)
                        .frame(width: 24, height: 24)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isChecked ? BSColors.micActive : BSColors.checkboxBorder, lineWidth: 2)
                        )
                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                    }
                }
                .onTapGesture {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isChecked.toggle() }
                }

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.black)
                        .lineLimit(1)
                    Text(category.label)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(category.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(category.color.opacity(0.12))
                        .cornerRadius(4)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
        }
    }
}

// MARK: - Live waveform

private struct BSWaveform: View {
    let levels: [CGFloat]

    var body: some View {
        GeometryReader { geo in
            let count = levels.count
            let spacing: CGFloat = 5
            let barWidth = max(3, (geo.size.width - spacing * CGFloat(max(count - 1, 0))) / CGFloat(max(count, 1)))

            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { index, level in
                    let h = max(4, level * geo.size.height)
                    RoundedRectangle(cornerRadius: barWidth / 2)
                        .fill(index % 6 == 0 ? BSColors.waveformSecondary : BSColors.waveformPrimary)
                        .frame(width: barWidth, height: h)
                        .animation(.easeOut(duration: 0.12), value: level)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
    }
}

// MARK: - Transcript → tasks parser (live heuristic, pre-Gemini)

enum BySayingParser {
    static func tasks(from transcript: String) -> [String] {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }

        var text = transcript
        for sep in [",", ";", "\n", " and ", " then ", " also ", ". ",
                    " и ", " потом ", " также ", " затем ", ". "] {
            text = text.replacingOccurrences(of: sep, with: "\n")
        }

        let fillers = [
            // English
            "i need to ", "i have to ", "i want to ", "i should ", "i must ",
            "remember to ", "remind me to ", "i'm going to ", "im going to ",
            "i would like to ", "let me ", "i gotta ", "i've got to ",
            // Russian
            "мне нужно ", "нужно ", "надо ", "я хочу ", "хочу ", "я должен ",
            "должен ", "напомни мне ", "напомни ", "я собираюсь ", "собираюсь ",
            "не забыть ", "не забудь "
        ]

        var result: [String] = []
        var seen = Set<String>()

        for raw in text.components(separatedBy: "\n") {
            var item = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !item.isEmpty else { continue }

            let lower = item.lowercased()
            for filler in fillers where lower.hasPrefix(filler) {
                item = String(item.dropFirst(filler.count))
                break
            }

            item = item.trimmingCharacters(in: CharacterSet(charactersIn: " .,!?"))
            guard item.count >= 2 else { continue }

            item = item.prefix(1).uppercased() + item.dropFirst()
            let key = item.lowercased()
            if !seen.contains(key) { seen.insert(key); result.append(item) }
        }
        return result
    }
}

#Preview {
    BySayingView()
}
