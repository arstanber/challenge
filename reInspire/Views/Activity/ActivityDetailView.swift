import SwiftUI

struct ActivityDetailView: View {
    @State private var vm: ActivityDetailViewModel
    @State private var showSubmitReport = false
    @State private var shareRequest: ShareRequest?
    // AI features (#11, #12)
    @State private var showFailureAnalysis = false
    @State private var showGoalSplit = false
    // Location reminder (#10)
    @State private var showLocationReminder = false
    // Habit calendar
    @State private var showHabitCalendar = false
    // Paywall when monthly AI quota is spent
    @State private var showPaywall = false

    init(activity: Activity, onReportSubmitted: (() -> Void)? = nil) {
        let viewModel = ActivityDetailViewModel(activity: activity)
        viewModel.onReportSubmitted = onReportSubmitted
        _vm = State(wrappedValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerSection
                statsSection
                if vm.isLoading {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    reportsSection
                }
            }
            .padding()
            .readableWidth()
        }
        .navigationTitle(vm.activity.title)
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            if vm.activity.status == .active {
                ToolbarItem(placement: .primaryAction) {
                    Button("Submit report") { Haptics.tap(); showSubmitReport = true }
                        .fontWeight(.semibold).foregroundStyle(.orange)
                }
            }
            // AI toolbar menu (#11 #12)
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    if vm.activity.type.hasStreak {
                        Button("Calendar & streak 🔥") { Haptics.tap(); showHabitCalendar = true }
                    }
                    if vm.activity.status == .failed {
                        Button("Why did I fail? 🔍") { Haptics.tap(); showFailureAnalysis = true }  // #11
                    }
                    if vm.activity.type == .goal {
                        Button("Break this goal down 🤖") { Haptics.tap(); showGoalSplit = true }   // #12
                    }
                    Button("Location reminder 📍") { Haptics.tap(); showLocationReminder = true }   // #10
                    Button("Поделиться 📤") {
                        Haptics.tap()
                        shareRequest = ShareRequest(
                            kind: .taskDone(title: vm.activity.title,
                                            streak: vm.activity.streakCurrent,
                                            connector: vm.activity.connector?.displayName),
                            name: AuthService.shared.currentUser?.displayLabel)
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $shareRequest) { req in
            ShareComposerView(kind: req.kind, name: req.name)
        }
        .sheet(isPresented: $showSubmitReport, onDismiss: {
            Task { await vm.loadReports() }
        }) {
            SubmitReportView(activity: vm.activity, onSubmit: { showSubmitReport = false }, vm: vm)
        }
        // AI: failure analysis (#11)
        .sheet(isPresented: $showFailureAnalysis) {
            FailureAnalysisSheet(activity: vm.activity)
        }
        // AI: goal split (#12)
        .sheet(isPresented: $showGoalSplit) {
            GoalSplitSheet(activity: vm.activity) { subtasks in
                Task {
                    await vm.createSubtasks(subtasks)
                    await vm.loadReports()
                }
            }
        }
        // Location reminder (#10)
        .sheet(isPresented: $showLocationReminder) {
            LocationReminderPicker(activity: vm.activity)
        }
        // Habit calendar + streak
        .fullScreenCover(isPresented: $showHabitCalendar, onDismiss: {
            Task { await vm.loadReports() }
        }) {
            HabitCalendarView(activity: vm.activity) {
                Task { await vm.loadReports() }
            }
        }
        .task { await vm.loadReports() }
        .alert("Лимит AI-проверок исчерпан", isPresented: $vm.aiLimitReached) {
            Button("reInspire Premium") { Haptics.tap(); showPaywall = true }
            Button("Позже", role: .cancel) {}
        } message: {
            Text("Бесплатные проверки фото на этот месяц закончились. Отчёт сохранён без проверки. В Premium проверки безлимитные.")
        }
        .sheet(isPresented: $showPaywall) {
            NavigationStack { PremiumView() }
        }
        .alert("Error", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { Haptics.tap(); vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: vm.activity.type.icon)
                    .font(.title2)
                    .foregroundStyle(typeColor)
                    .frame(width: 44, height: 44)
                    .background(typeColor.opacity(0.15), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.activity.type.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    StatusBadge(status: vm.activity.status)
                }

                Spacer()

                if let deadline = vm.activity.deadline {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Deadline")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text(deadline, style: .date)
                            .font(.caption.bold())
                    }
                }
            }

            if !vm.activity.description.isEmpty {
                Text(vm.activity.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if let condition = vm.activity.condition {
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.caption)
                        .foregroundStyle(.purple)
                    Text("AI condition: \(condition)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .background(.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }

            if vm.activity.isFromParent {
                Label("Assigned by parent", systemImage: "person.2.fill")
                    .font(.caption)
                    .foregroundStyle(.pink)
            }
        }
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.separator, lineWidth: 0.5))
    }

    private var statsSection: some View {
        VStack(spacing: 12) {
            if vm.activity.type == .goal, let target = vm.activity.goalTarget {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Progress")
                            .font(.subheadline.bold())
                        Spacer()
                        Text(String(format: "%.0f / %.0f", vm.activity.goalProgress, target))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    ProgressView(value: vm.activity.progressFraction)
                        .tint(Color(hex: "0048E2"))
                        .scaleEffect(x: 1, y: 1.5)
                }
                .padding(14)
                .background(.background, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator, lineWidth: 0.5))
            }
        }
    }

    private var reportsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reports (\(vm.reports.count))")
                .font(.headline)

            if vm.reports.isEmpty {
                Text("No reports yet. Submit your first one!")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
            } else {
                ForEach(vm.reports) { report in
                    ReportRowView(report: report)
                }
            }
        }
    }

    private var typeColor: Color {
        switch vm.activity.type {
        case .challenge: return Color(hex: "0048E2")
        case .goal: return .green
        case .task: return .orange
        case .habit: return .purple
        case .assignment: return .pink
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
            Text(value)
                .font(.title.bold())
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator, lineWidth: 0.5))
    }
}

struct ReportRowView: View {
    let report: Report

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(report.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if report.aiResult != .notApplicable {
                    Image(systemName: report.aiResult.icon)
                        .foregroundStyle(aiColor)
                }
            }

            if let urlStr = report.photoURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity)
                        .frame(height: 180)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } placeholder: {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.fill.tertiary)
                        .frame(height: 180)
                        .overlay { ProgressView() }
                }
            }

            if let comment = report.comment {
                Text(comment).font(.subheadline)
            }

            if report.aiResult != .notApplicable {
                AIResultView(result: report.aiResult, explanation: report.aiExplanation)
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.separator, lineWidth: 0.5))
    }

    private var aiColor: Color {
        switch report.aiResult {
        case .approved:      return .green
        case .rejected:      return .red
        case .pending:       return .orange
        case .notApplicable: return Color(hex: "0048E2")
        case .excused:       return .purple
        }
    }
}
