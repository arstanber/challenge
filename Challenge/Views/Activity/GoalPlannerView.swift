import SwiftUI

struct GoalPlannerView: View {
    @State private var vm = GoalPlannerViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch vm.step {
                case .describe, .loadingQuestions:
                    DescribeGoalView(vm: vm)
                case .questions:
                    QuestionsView(vm: vm)
                case .generatingPlan:
                    AIThinkingView(message: "Строим твой план")
                case .plan:
                    PlanPreviewView(vm: vm)
                case .creating:
                    AIThinkingView(message: "Создаём \(vm.plan?.activities.count ?? 0) задач")
                case .done:
                    DoneView(vm: vm, onDismiss: { dismiss() })
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if vm.step != .done {
                        Button("Отмена") { Haptics.tap(); dismiss() }
                    }
                }
            }
            .alert("Ошибка", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("ОК") { Haptics.tap(); vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    private var navTitle: String {
        switch vm.step {
        case .describe: return "The Challenge."
        case .loadingQuestions, .questions: return "The Challenge."
        case .generatingPlan, .plan: return "Твой план"
        case .creating, .done: return "Создаём план"
        }
    }
}

// MARK: - Arc motion (blob follows a circular arc path)

private struct ArcMotionEffect: GeometryEffect {
    /// Animatable parameter 0 → 1 (maps to the arc sweep angle).
    var phase: CGFloat

    var animatableData: CGFloat {
        get { phase }
        set { phase = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        // Convert phase 0…1 → angle -sweep…+sweep radians
        let sweep: CGFloat = 0.52           // ±0.52 rad ≈ ±30°
        let angle = (phase * 2 - 1) * sweep
        let radius: CGFloat = 320           // arc radius

        // Arc: circle center is directly below current position, blob traces bottom.
        // x grows linearly with angle; y increases toward the sides (∪ shape).
        let x = radius * sin(angle)
        let y = 295 + radius * (1 - cos(angle))   // 295 = base vertical offset

        return ProjectionTransform(CGAffineTransform(translationX: x, y: y))
    }
}

private struct AIBlobView: View {
    @State private var phase: CGFloat = 0

    var body: some View {
        Ellipse()
            .fill(Color(hex: "0048E2").opacity(0.30))
            .frame(width: 534, height: 510)
            .blur(radius: 40)
            .modifier(ArcMotionEffect(phase: phase))
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 3.5).repeatForever(autoreverses: true)
                ) { phase = 1 }
            }
    }
}

// MARK: - Step 1: Describe

private enum AIPlanColors {
    static let background = Color(red: 0.962, green: 0.962, blue: 0.962)
    static let placeholderGray = Color(red: 0.75, green: 0.75, blue: 0.75)
    static let buttonBackground = Color(red: 0.872, green: 0.872, blue: 0.872)
    static let buttonBorder = Color(red: 0.675, green: 0.675, blue: 0.675)
    static let analyzeTextGray = Color(red: 0.536, green: 0.536, blue: 0.536)
    static let blueAccent = Color(red: 0.0, green: 0.282, blue: 0.886)
    static let glassButtonBg = Color(red: 0.970, green: 0.970, blue: 0.970)
    static let glassButtonBorder = Color(red: 0.867, green: 0.867, blue: 0.867)
}

private struct DescribeGoalView: View {
    @Bindable var vm: GoalPlannerViewModel
    @State private var showDeadlinePicker = false

    private var isLoading: Bool { vm.step == .loadingQuestions }

    private var deadlineLabel: String? {
        guard let deadline = vm.deadline else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "d MMM"
        return f.string(from: deadline)
    }

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 50)
                        .fill(AIPlanColors.background)
                        .ignoresSafeArea(edges: .bottom)

                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: 10) {
                            AIPlanGlassButton()
                            Text("ИИ шаг за шагом")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.black)
                        }
                        .padding(.top, 28)
                        .padding(.leading, 24)

                        ZStack(alignment: .topLeading) {
                            if vm.goalDescription.isEmpty {
                                Text("Напиши новую задачу...")
                                    .font(.system(size: 32, weight: .medium))
                                    .foregroundColor(AIPlanColors.placeholderGray)
                                    .padding(.top, 20)
                                    .padding(.leading, 24)
                                    .allowsHitTesting(false)
                            }
                            TextEditor(text: $vm.goalDescription)
                                .font(.system(size: 32, weight: .medium))
                                .foregroundColor(.black)
                                .scrollContentBackground(.hidden)
                                .background(Color.clear)
                                .padding(.top, 12)
                                .padding(.horizontal, 20)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .disabled(isLoading)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                        // Bottom gradient aura when loading
                        .overlay(alignment: .bottom) {
                            if isLoading {
                                AIBlobView()
                                    .transition(.opacity.animation(.easeIn(duration: 0.4)))
                                    .allowsHitTesting(false)
                            }
                        }

                        HStack(spacing: 8) {
                            Button {
                                Haptics.tap()
                                showDeadlinePicker = true
                            } label: {
                                ZStack(alignment: .topTrailing) {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(AIPlanColors.buttonBackground)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(vm.deadline != nil ? AIPlanColors.blueAccent : AIPlanColors.buttonBorder, lineWidth: vm.deadline != nil ? 1.5 : 1))
                                    Image(systemName: vm.deadline != nil ? "clock.fill" : "clock.badge.plus")
                                        .resizable().scaledToFit()
                                        .foregroundColor(vm.deadline != nil ? AIPlanColors.blueAccent : AIPlanColors.analyzeTextGray)
                                        .frame(width: 22, height: 22)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)

                                    if let deadlineLabel {
                                        Text(deadlineLabel)
                                            .font(.system(size: 9, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 5)
                                            .padding(.vertical, 2)
                                            .background(AIPlanColors.blueAccent)
                                            .clipShape(Capsule())
                                            .offset(x: 8, y: -6)
                                    }
                                }
                                .frame(width: 62, height: 60)
                            }
                            .buttonStyle(PressableButtonStyle())
                            .disabled(isLoading)

                            Button { Task { await vm.loadQuestions() } } label: {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(vm.canProceedFromDescribe ? Color.black : AIPlanColors.buttonBackground)
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(vm.canProceedFromDescribe ? Color.clear : AIPlanColors.buttonBorder, lineWidth: 1))
                                    if isLoading {
                                        ProgressView().tint(.white)
                                    } else {
                                        HStack(spacing: 6) {
                                            Text("Анализировать")
                                                .font(.system(size: 18, weight: .medium))
                                                .foregroundColor(vm.canProceedFromDescribe ? .white : AIPlanColors.analyzeTextGray)
                                            Image(systemName: "sparkles")
                                                .font(.system(size: 14, weight: .medium))
                                                .foregroundColor(vm.canProceedFromDescribe ? .white : AIPlanColors.analyzeTextGray)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity).frame(height: 60)
                            }
                            .buttonStyle(PressableButtonStyle())
                            .disabled(!vm.canProceedFromDescribe || isLoading)
                        }
                        .padding(.horizontal, 20)
                        .padding(.bottom, 28)
                    }
                    .readableWidth()
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isLoading)
        .sheet(isPresented: $showDeadlinePicker) {
            GoalDeadlinePickerView(deadline: $vm.deadline)
                .presentationDetents([.medium])
        }
    }
}

// MARK: - Deadline picker sheet

private struct GoalDeadlinePickerView: View {
    @Binding var deadline: Date?
    @Environment(\.dismiss) private var dismiss
    @State private var selection: Date

    private static var tomorrow: Date {
        Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    }

    init(deadline: Binding<Date?>) {
        self._deadline = deadline
        self._selection = State(initialValue: deadline.wrappedValue ?? Self.tomorrow)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                DatePicker(
                    "Дедлайн цели",
                    selection: $selection,
                    in: Self.tomorrow...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .environment(\.locale, Locale(identifier: "ru_RU"))
                .padding(.horizontal, 16)
                .padding(.top, 8)

                Spacer()
            }
            .navigationTitle("Дедлайн цели")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if deadline != nil {
                        Button("Убрать", role: .destructive) {
                            Haptics.tap()
                            deadline = nil
                            dismiss()
                        }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") {
                        Haptics.tap()
                        deadline = selection
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct AIPlanGlassButton: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(AIPlanColors.glassButtonBg)
                .frame(width: 42, height: 42)
                .overlay(Circle().fill(Color.white.opacity(0.65)))
                .overlay(Circle().stroke(AIPlanColors.glassButtonBorder, lineWidth: 0.5))
            ZStack {
                Image(systemName: "sparkle")
                    .resizable().scaledToFit()
                    .foregroundColor(AIPlanColors.blueAccent)
                    .frame(width: 10, height: 10)
                    .offset(x: 5, y: -5)
                Image(systemName: "sparkle")
                    .resizable().scaledToFit()
                    .foregroundColor(.black)
                    .frame(width: 18, height: 18)
                    .offset(x: -2, y: 2)
            }
            .frame(width: 24, height: 24)
        }
        .frame(width: 42, height: 42)
    }
}

// MARK: - Step 2: Questions (one at a time)

private enum QColors {
    static let blue = Color(red: 0.0, green: 0.282, blue: 0.886)
    static let buttonBg = Color(red: 0.872, green: 0.872, blue: 0.872)
    static let buttonBorder = Color(red: 0.675, green: 0.675, blue: 0.675)
    static let grayText = Color(red: 0.536, green: 0.536, blue: 0.536)
}

private struct QuestionsView: View {
    @Bindable var vm: GoalPlannerViewModel
    @State private var currentIndex = 0
    @FocusState private var isFocused: Bool

    private var total: Int { vm.answers.count }
    private var isLast: Bool { currentIndex == total - 1 }
    private var currentAnswer: Binding<String> {
        Binding(
            get: { currentIndex < total ? vm.answers[currentIndex].answer : "" },
            set: { if currentIndex < total { vm.answers[currentIndex].answer = $0 } }
        )
    }
    private var canAdvance: Bool {
        !currentAnswer.wrappedValue.trimmingCharacters(in: .whitespaces).isEmpty
    }
    private var questionText: AttributedString {
        var num = AttributedString("\(currentIndex + 1). ")
        num.font = .system(size: 24, weight: .bold)
        num.foregroundColor = .white
        var q = AttributedString(currentIndex < total ? vm.answers[currentIndex].question : "")
        q.font = .system(size: 24, weight: .regular)
        q.foregroundColor = .white
        return num + q
    }

    var body: some View {
        ZStack {
            QColors.blue.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                // Progress + back chevron
                HStack(spacing: 10) {
                    if currentIndex > 0 {
                        Button {
                            Haptics.tap()
                            isFocused = false
                            withAnimation { currentIndex -= 1 }
                        } label: {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 34, height: 34)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())
                        }
                    }
                    HStack(spacing: 6) {
                        ForEach(0..<total, id: \.self) { i in
                            Capsule()
                                .fill(i <= currentIndex ? Color.white : Color.white.opacity(0.3))
                                .frame(height: 4)
                                .animation(.easeInOut(duration: 0.25), value: currentIndex)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .padding(.top, 64)
                .padding(.horizontal, 24)

                // Header
                Text("Хорошая задача!\nНужно задать пару вопросов.")
                    .font(.system(size: 24, weight: .medium))
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 24)
                    .padding(.horizontal, 24)

                // Question
                if currentIndex < total {
                    Text(questionText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)
                        .padding(.horizontal, 24)
                        .id("q-\(currentIndex)")
                }

                // Answer field
                ZStack(alignment: .topLeading) {
                    if currentAnswer.wrappedValue.isEmpty {
                        Text("Твой ответ...")
                            .font(.system(size: 28, weight: .medium))
                            .foregroundColor(.white.opacity(0.45))
                            .padding(.top, 8)
                            .padding(.leading, 4)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: currentAnswer)
                        .font(.system(size: 28, weight: .medium))
                        .foregroundColor(.white)
                        .tint(.white)
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                        .focused($isFocused)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .padding(.top, 12)
                .padding(.horizontal, 20)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear { isFocused = true }

                // Next / Generate button
                Button {
                    isFocused = false
                    if isLast {
                        Task { await vm.generatePlan() }
                    } else {
                        withAnimation(.easeInOut(duration: 0.3)) { currentIndex += 1 }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(isLast ? "Сгенерировать" : "Далее")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundColor(canAdvance ? .white : QColors.grayText)
                        Image(systemName: "sparkle")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(canAdvance ? .white : QColors.grayText)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(canAdvance ? Color.black : QColors.buttonBg)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(canAdvance ? Color.clear : QColors.buttonBorder, lineWidth: 1)
                    )
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(!canAdvance)
                .padding(.horizontal, 12)
                .padding(.bottom, 32)
            }
            .readableWidth()
        }
    }
}

// MARK: - Step 3: Plan Preview

private enum PPColors {
    static let cardBlue = Color(red: 0.0, green: 0.282, blue: 0.886)
    static let tagHealth = Color(red: 0.475, green: 0.566, blue: 0.973)
    static let tagDurationText = Color(red: 0.664, green: 0.0, blue: 0.011)
    static let addTaskBg = Color(red: 0.872, green: 0.872, blue: 0.872)
    static let addTaskBorder = Color(red: 0.675, green: 0.675, blue: 0.675)
    static let addTaskText = Color(red: 0.536, green: 0.536, blue: 0.536)
    static let checkboxBorder = Color(red: 0.839, green: 0.839, blue: 0.839)
}

private struct PlanPreviewView: View {
    let vm: GoalPlannerViewModel

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            if let plan = vm.plan {
                VStack(spacing: 0) {
                    // Blue card
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 50)
                            .fill(PPColors.cardBlue)
                            .padding(.horizontal, 15)
                            .ignoresSafeArea(edges: .bottom)

                        VStack(alignment: .leading, spacing: 0) {
                            // Header
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Новая цель")
                                    .font(.system(size: 34, weight: .bold))
                                    .italic()
                                    .foregroundColor(.white)
                                Text(plan.title)
                                    .font(.system(size: 34, weight: .regular))
                                    .italic()
                                    .foregroundColor(.white)
                                    .lineLimit(3)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(.top, 36)
                            .padding(.horizontal, 36)

                            Text("Задачи для достижения цели:")
                                .font(.system(size: 20, weight: .medium))
                                .foregroundColor(.white)
                                .padding(.top, 20)
                                .padding(.horizontal, 36)

                            // Task cards
                            ScrollView(showsIndicators: false) {
                                VStack(spacing: 16) {
                                    ForEach(plan.activities.sorted { $0.stepNumber < $1.stepNumber }) { activity in
                                        PPTaskCard(activity: activity)
                                            .padding(.horizontal, 4)
                                    }
                                }
                                .padding(.top, 20)
                                .padding(.horizontal, 32)
                                .padding(.bottom, 32)
                            }
                        }
                    }

                    // Add tasks button
                    Button {
                        Task { await vm.createActivities() }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 12)
                                .fill(PPColors.addTaskBg)
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(PPColors.addTaskBorder, lineWidth: 1))
                            if vm.step == .creating {
                                ProgressView().tint(PPColors.addTaskText)
                            } else {
                                Text("Добавить задачи ✦")
                                    .font(.system(size: 18, weight: .medium))
                                    .foregroundColor(PPColors.addTaskText)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 60)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .padding(.horizontal, 22)
                    .padding(.bottom, 16)
                    .padding(.top, 12)
                    .disabled(vm.step == .creating)
                }
                .readableWidth()
            }
        }
        .onAppear { Haptics.success() }
    }
}

private struct PPTaskCard: View {
    let activity: PlannedActivity
    @State private var isChecked = false

    private var scheduleLabel: String { activity.frequency.displayName }
    private var durationLabel: String {
        if let days = activity.deadlineDays { return "\(days) дн." }
        return activity.frequency == .once ? "разово" : "постоянно"
    }
    private var categoryColor: Color { activity.type.stepColor }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 15)
                .fill(Color.white)
                .frame(height: 74)
                .shadow(color: .black.opacity(0.06), radius: 6, x: 0, y: 2)

            HStack(spacing: 12) {
                // Checkbox
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.white)
                        .frame(width: 24, height: 24)
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(PPColors.checkboxBorder, lineWidth: 2))
                    if isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(PPColors.cardBlue)
                    }
                }
                .onTapGesture { Haptics.selection(); withAnimation { isChecked.toggle() } }
                .padding(.leading, 12)

                VStack(alignment: .leading, spacing: 6) {
                    Text(activity.title)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(.black)
                        .lineLimit(1)

                    HStack(spacing: 6) {
                        // Category
                        Text(activity.type.displayName.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(categoryColor)
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .background(categoryColor.opacity(0.10))
                            .cornerRadius(4)

                        // Schedule
                        Text(scheduleLabel.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .background(Color.black)
                            .cornerRadius(4)

                        // Duration
                        Text(durationLabel.uppercased())
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(PPColors.tagDurationText)
                            .padding(.horizontal, 6).padding(.vertical, 4)
                            .background(Color.gray.opacity(0.1))
                            .cornerRadius(4)
                    }
                }

                Spacer()
            }
            .frame(height: 74)
        }
    }
}

// MARK: - Loading

private struct AIThinkingView: View {
    let message: String
    @State private var dots = ""
    @State private var dotTimer: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.orange.opacity(0.1))
                    .frame(width: 90, height: 90)
                Image(systemName: "sparkles")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                    .symbolEffect(.pulse)
            }
            Text(message + dots)
                .font(.headline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { startDots() }
        .onDisappear { dotTimer?.cancel() }
    }

    private func startDots() {
        dotTimer = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                dots = dots.count < 3 ? dots + "." : ""
            }
        }
    }
}

// MARK: - Done

private struct DoneView: View {
    let vm: GoalPlannerViewModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 28) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.1))
                    .frame(width: 110, height: 110)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(.green)
            }
            VStack(spacing: 8) {
                Text("План создан!")
                    .font(.title.bold())
                Text("Добавлено задач в твой список: \(vm.createdCount).")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let title = vm.plan?.title {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 4)
                }
            }
            Button {
                onDismiss()
            } label: {
                Text("Погнали! 🔥")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 40)
            .readableWidth(480)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ActivityType color extension

private extension ActivityType {
    var stepColor: Color {
        switch self {
        case .challenge: return .orange
        case .goal: return Color(hex: "0048E2")
        case .task: return .green
        case .habit: return .purple
        case .assignment: return .pink
        }
    }
}

#Preview {
    GoalPlannerView()
        .environment(AuthService.shared)
}
