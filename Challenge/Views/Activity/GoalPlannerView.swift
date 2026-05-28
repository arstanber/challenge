import SwiftUI

struct GoalPlannerView: View {
    @State private var vm = GoalPlannerViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                switch vm.step {
                case .describe:
                    DescribeGoalView(vm: vm)
                case .loadingQuestions:
                    AIThinkingView(message: "Analyzing your goal…")
                case .questions:
                    QuestionsView(vm: vm)
                case .generatingPlan:
                    AIThinkingView(message: "Building your plan…")
                case .plan:
                    PlanPreviewView(vm: vm)
                case .creating:
                    AIThinkingView(message: "Creating \(vm.plan?.activities.count ?? 0) activities…")
                case .done:
                    DoneView(vm: vm, onDismiss: { dismiss() })
                }
            }
            .navigationTitle(navTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if vm.step != .done {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
    }

    private var navTitle: String {
        switch vm.step {
        case .describe: return "AI Goal Planner"
        case .loadingQuestions, .questions: return "Clarify Your Goal"
        case .generatingPlan, .plan: return "Your Plan"
        case .creating, .done: return "Creating Plan"
        }
    }
}

// MARK: - Step 1: Describe

private struct DescribeGoalView: View {
    @Bindable var vm: GoalPlannerViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.orange)
                        Text("Describe your goal")
                            .font(.title2).bold()
                    }
                    Text("Tell Claude what you want to achieve. Be as specific as possible — the more detail, the better the plan.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Text editor
                VStack(alignment: .leading, spacing: 8) {
                    Text("What is your goal?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    ZStack(alignment: .topLeading) {
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(.systemGray6))
                        if vm.goalDescription.isEmpty {
                            Text("e.g. I want to lose weight to 80 kg by summer through healthy eating and daily exercise")
                                .foregroundStyle(.tertiary)
                                .padding(14)
                                .allowsHitTesting(false)
                        }
                        TextEditor(text: $vm.goalDescription)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(minHeight: 140)
                    }
                    .frame(minHeight: 140)
                }

                // Examples
                VStack(alignment: .leading, spacing: 8) {
                    Text("Examples")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    ForEach(examples, id: \.self) { example in
                        Button {
                            vm.goalDescription = example
                        } label: {
                            HStack {
                                Image(systemName: "lightbulb.fill")
                                    .foregroundStyle(.yellow)
                                    .font(.caption)
                                Text(example)
                                    .font(.subheadline)
                                    .foregroundStyle(.primary)
                                    .multilineTextAlignment(.leading)
                                Spacer()
                            }
                            .padding(12)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }

                // CTA
                Button {
                    Task { await vm.loadQuestions() }
                } label: {
                    HStack {
                        Image(systemName: "sparkles")
                        Text("Analyze with AI")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(vm.canProceedFromDescribe ? Color.orange : Color.gray.opacity(0.3))
                    .foregroundStyle(vm.canProceedFromDescribe ? .white : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!vm.canProceedFromDescribe)
            }
            .padding()
        }
    }

    private let examples = [
        "I want to lose weight to 80 kg by September through diet and daily runs",
        "I want to read 20 books this year, starting with philosophy",
        "I want to run a 5K in under 30 minutes within 3 months",
        "I want to learn Spanish to conversational level in 6 months"
    ]
}

// MARK: - Step 2: Questions

private struct QuestionsView: View {
    @Bindable var vm: GoalPlannerViewModel
    @FocusState private var focusedIndex: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // Header
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "text.bubble.fill")
                            .foregroundStyle(.blue)
                        Text("A few questions")
                            .font(.title2).bold()
                    }
                    Text("Claude needs a bit more info to build the perfect plan for you.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                // Goal recap chip
                Label(vm.goalDescription, systemImage: "flag.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                    .lineLimit(2)

                // Questions
                ForEach($vm.answers) { $answer in
                    let idx = vm.answers.firstIndex(where: { $0.id == answer.id }) ?? 0
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .top, spacing: 8) {
                            Text("\(idx + 1)")
                                .font(.caption.bold())
                                .foregroundStyle(.white)
                                .frame(width: 22, height: 22)
                                .background(Color.blue, in: Circle())
                            Text(answer.question)
                                .font(.subheadline.weight(.medium))
                        }
                        TextField("Your answer…", text: $answer.answer, axis: .vertical)
                            .lineLimit(2...4)
                            .padding(12)
                            .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 10))
                            .focused($focusedIndex, equals: idx)
                    }
                }

                // CTA
                Button {
                    focusedIndex = nil
                    Task { await vm.generatePlan() }
                } label: {
                    HStack {
                        Image(systemName: "wand.and.stars")
                        Text("Generate Plan")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(vm.canProceedFromQuestions ? Color.blue : Color.gray.opacity(0.3))
                    .foregroundStyle(vm.canProceedFromQuestions ? .white : .secondary)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!vm.canProceedFromQuestions)
            }
            .padding()
        }
    }
}

// MARK: - Step 3: Plan Preview

private struct PlanPreviewView: View {
    let vm: GoalPlannerViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let plan = vm.plan {
                    planContent(plan: plan)
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func planContent(plan: GoalPlanResponse) -> some View {
                // Plan header
                VStack(alignment: .leading, spacing: 6) {
                    Text(plan.title)
                        .font(.title2).bold()
                    Text(plan.summary)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    LinearGradient(colors: [.orange.opacity(0.15), .clear], startPoint: .top, endPoint: .bottom),
                    in: RoundedRectangle(cornerRadius: 16)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16).stroke(Color.orange.opacity(0.3), lineWidth: 1)
                )

                // Activity ladder
                Text("Your \(plan.activities.count)-step ladder")
                    .font(.headline)

                VStack(spacing: 0) {
                    ForEach(plan.activities.sorted(by: { $0.stepNumber < $1.stepNumber })) { activity in
                        PlannedActivityCard(activity: activity, isLast: activity.stepNumber == plan.activities.count)
                    }
                }

                // CTA
                Button {
                    Task { await vm.createActivities() }
                } label: {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Create All \(plan.activities.count) Activities")
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
    }
}

private struct PlannedActivityCard: View {
    let activity: PlannedActivity
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Step indicator + line
            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(activity.type.stepColor.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: activity.type.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(activity.type.stepColor)
                }
                if !isLast {
                    Rectangle()
                        .fill(Color(.systemGray4))
                        .frame(width: 2)
                        .frame(maxHeight: .infinity)
                        .padding(.vertical, 4)
                }
            }
            .frame(width: 36)

            // Card content
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Step \(activity.stepNumber)")
                        .font(.caption.bold())
                        .foregroundStyle(activity.type.stepColor)
                    Spacer()
                    TypeBadge(type: activity.type, frequency: activity.frequency)
                }
                Text(activity.title)
                    .font(.subheadline.bold())
                Text(activity.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let days = activity.deadlineDays {
                    Label("\(days) days to complete", systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let target = activity.goalTarget {
                    Label("Target: \(target.formatted())", systemImage: "target")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                if let condition = activity.condition {
                    Label(condition, systemImage: "camera.fill")
                        .font(.caption2)
                        .foregroundStyle(.blue.opacity(0.8))
                }
            }
            .padding(.bottom, isLast ? 0 : 16)
        }
    }
}

private struct TypeBadge: View {
    let type: ActivityType
    let frequency: ActivityFrequency

    var body: some View {
        HStack(spacing: 4) {
            Text(type.displayName)
            Text("·")
            Text(frequency.displayName)
        }
        .font(.caption2)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(type.stepColor.opacity(0.12), in: Capsule())
        .foregroundStyle(type.stepColor)
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
                Text("Plan Created!")
                    .font(.title.bold())
                Text("\(vm.createdCount) activities added to your list.")
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
                Text("Let's go! 🔥")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.orange)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 40)
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
        case .goal: return .blue
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
