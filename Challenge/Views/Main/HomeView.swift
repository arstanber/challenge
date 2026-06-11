import SwiftUI

// MARK: - Design tokens
private enum AppColors {
    static let background     = Color(.systemBackground)
    static let cardBg         = Color(.secondarySystemBackground)
    static let headerBlue     = Color(red: 0, green: 0.280, blue: 0.886).opacity(0.55)
    static let challengeLabel = Color(red: 0, green: 0.280, blue: 0.886)
    static let buttonBg       = Color(.secondarySystemBackground)
    static let separatorLine  = Color.primary.opacity(0.12)
}

private enum AppSpacing {
    static let buttonSize: CGFloat = 68
    static let wideButtonWidth: CGFloat = 135
}

// MARK: - Per-type accent + number formatting

private func typeAccent(_ type: ActivityType) -> Color {
    switch type {
    case .challenge:  return Color(hex: "0048E2")
    case .goal:       return Color(hex: "2FB873")
    case .task:       return Color(hex: "FF7A00")
    case .habit:      return Color(hex: "8B5CF6")
    case .assignment: return Color(hex: "EC4899")
    }
}

private let groupedFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = " "
    f.maximumFractionDigits = 0
    return f
}()

private func grouped(_ value: Double) -> String {
    groupedFormatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
}

// MARK: - Home

struct HomeView: View {
    @State private var vm = ActivitiesViewModel()
    @AppStorage("requirePhotoVerification") private var requirePhoto = true

    // Creation
    @State private var showAIPlanner = false
    @State private var showBySaying = false
    @State private var showCreateMenu = false
    @State private var showAddHabit = false
    @State private var newHabitDraft: HabitDraft?
    // Navigation
    @State private var showSettings = false
    // Task interaction
    @State private var taskToComplete: Activity?
    @State private var lastPhotoTask: Activity?
    @State private var cancelledTaskId: UUID?
    @State private var editingActivity: Activity?
    @State private var detailActivity: Activity?
    @State private var deletingActivity: Activity?
    // Celebration
    @State private var confettiTrigger = 0
    @State private var showPerfectDay = false

    // MARK: Derived data

    private var activeTasks: [Activity] {
        (vm.myActivities + vm.parentActivities)
            .filter { $0.status == .active }
            .filter { !vm.isHandledToday($0.id) }
    }

    /// Parents that are still active -- children of completed/deleted goals are
    /// orphans and must surface as top-level cards, not vanish.
    private var activeParentIds: Set<UUID> {
        Set(activeTasks.filter { $0.parentId == nil }.map(\.id))
    }

    private func isTopLevel(_ a: Activity) -> Bool {
        guard let parentId = a.parentId else { return true }
        return !activeParentIds.contains(parentId)
    }

    private var todayTasks: [Activity] {
        let cal = Calendar.current
        let endOfToday = cal.date(bySettingHour: 23, minute: 59, second: 59, of: Date())!
        return activeTasks.filter { a in
            guard isTopLevel(a) else { return false }
            if a.type == .goal, activeTasks.contains(where: { $0.parentId == a.id }) { return true }
            if a.frequency == .once {
                guard let d = a.deadline else { return true }
                return d <= endOfToday
            }
            // Recurring: only on scheduled weekdays; deadline is an expiry
            // date ("repeat until"), not a due date.
            guard a.isScheduled(on: Date()) else { return false }
            if let d = a.deadline, d < Date() { return false }
            return true
        }
    }

    private var upcomingTasks: [Activity] {
        let cal = Calendar.current
        let endOfToday = cal.date(bySettingHour: 23, minute: 59, second: 59, of: Date())!
        return activeTasks.filter { a in
            guard isTopLevel(a) else { return false }
            // Off-day recurring tasks are intentionally absent from Home entirely.
            guard a.frequency == .once else { return false }
            guard let d = a.deadline else { return false }
            return d > endOfToday
        }
    }

    private func pendingSubtasks(of parent: Activity) -> [Activity] {
        activeTasks.filter { $0.parentId == parent.id }
    }

    /// True when every top-level task due today is done.
    private var allDone: Bool {
        let done = vm.todayDoneTopLevelCount
        let total = done + todayTasks.count
        return total > 0 && done == total
    }

    private var todayLabel: String {
        let f = DateFormatter()
        f.locale = .current
        f.dateFormat = "d MMMM"
        return f.string(from: Date())
    }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .top) {
            AppColors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    if vm.isLoading && activeTasks.isEmpty {
                        ProgressView().padding(.top, 60)
                    } else if todayTasks.isEmpty && upcomingTasks.isEmpty {
                        EmptyTodayView()
                            .padding(.top, 40)
                    } else {
                        ForEach(Array(todayTasks.enumerated()), id: \.element.id) { idx, task in
                            TaskCardView(
                                task: task,
                                subtasks: pendingSubtasks(of: task),
                                isDone: { vm.isDoneToday($0.id) },
                                onOpen: { detailActivity = task },
                                onToggle: completeTask,
                                onEdit: { editingActivity = $0 },
                                onDelete: { act in deletingActivity = act },
                                onTomorrow: { act in Task { await vm.moveToTomorrow(act); await vm.loadActivities() } },
                                cancelledTaskId: cancelledTaskId
                            )
                            .appearEffect(delay: 0.1 + Double(idx) * 0.05)
                        }

                        if !upcomingTasks.isEmpty {
                            Text("Upcoming")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                                .padding(.top, 6)

                            ForEach(Array(upcomingTasks.enumerated()), id: \.element.id) { idx, task in
                                TaskCardView(
                                    task: task,
                                    subtasks: pendingSubtasks(of: task),
                                    isDone: { vm.isDoneToday($0.id) },
                                    onOpen: { detailActivity = task },
                                    onToggle: completeTask,
                                    onEdit: { editingActivity = $0 },
                                    onDelete: { act in deletingActivity = act },
                                    onTomorrow: { act in Task { await vm.moveToTomorrow(act); await vm.loadActivities() } },
                                    cancelledTaskId: cancelledTaskId
                                )
                                .appearEffect(delay: 0.16 + Double(idx) * 0.05)
                            }
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 84)
                .padding(.bottom, 20)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HomeTopBar(dateLabel: todayLabel, count: todayTasks.count,
                           allDone: allDone, streak: vm.globalStreakCurrent)
            }

            ConfettiView(trigger: confettiTrigger)
                .ignoresSafeArea().zIndex(20).allowsHitTesting(false)

            if showCreateMenu {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .hapticTap { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showCreateMenu = false } }
                    .zIndex(40)
                VStack {
                    Spacer()
                    CreationMenuPopup(
                        onAIStepByStep: { showCreateMenu = false; after { showAIPlanner = true } },
                        onBySaying: { showCreateMenu = false; after { showBySaying = true } },
                        onByYourself: { showCreateMenu = false; after { newHabitDraft = HabitDraft() } }
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 100)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .zIndex(41)
            }
        }
        // "The Challenge." tucked under the Dynamic Island
        .overlay(alignment: .top) {
            Text("The Challenge.")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.top, 14)
                .ignoresSafeArea(.container, edges: .top)
        }
        // Bottom create buttons, always above the home indicator
        .safeAreaInset(edge: .bottom) {
            BottomButtons(
                onSettings: { Haptics.tap(); showSettings = true },
                onAI: { Haptics.tap(); showAIPlanner = true },
                onPlus: { Haptics.tap(); showAddHabit = true }
            )
            .padding(.bottom, 6)
        }
        .onChange(of: todayTasks.isEmpty) { wasEmpty, isEmpty in
            if isEmpty && !wasEmpty && !vm.isLoading {
                confettiTrigger += 1
                Haptics.success()
                NotificationService.shared.cancelStreakNudge()
                withAnimation { showPerfectDay = true }
            }
        }
        .task {
            await vm.loadActivities()
            NotificationService.shared.syncReminders(for: vm.myActivities + vm.parentActivities)
        }
        .fullScreenCover(isPresented: $showPerfectDay) {
            PerfectDayView { showPerfectDay = false }
                .presentationBackground(.clear)
        }
        .fullScreenCover(item: $detailActivity) { activity in
            HabitCalendarView(activity: activity) {
                Task { await vm.loadActivities() }
            }
        }
        .sheet(isPresented: $showAddHabit, onDismiss: reload) {
            AddHabitView(
                onPick: { draft in
                    showAddHabit = false
                    after { newHabitDraft = draft }
                },
                onCustom: {
                    showAddHabit = false
                    after { withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showCreateMenu = true } }
                }
            )
        }
        .sheet(item: $newHabitDraft, onDismiss: reload) { draft in
            NewHabitView(draft: draft, vm: vm) { Task { await vm.loadActivities() } }
        }
        .sheet(isPresented: $showAIPlanner, onDismiss: reload) { GoalPlannerView() }
        .sheet(isPresented: $showBySaying, onDismiss: reload) { BySayingView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $editingActivity) { activity in
            EditTaskView(activity: activity) { title, frequency, deadline, reminderTime, scheduleDays in
                Task { await vm.updateActivity(activity, title: title, frequency: frequency, deadline: deadline, reminderTime: reminderTime, scheduleDays: scheduleDays) }
            }
        }
        .sheet(item: $deletingActivity) { activity in
            DeleteReasonSheet(activityTitle: activity.title) { reason in
                Task { await vm.deleteActivity(activity, reason: reason) }
            }
        }
        .sheet(item: $taskToComplete, onDismiss: {
            // If lastPhotoTask is still set, the sheet closed without submitting a photo
            if let cancelled = lastPhotoTask {
                lastPhotoTask = nil
                cancelledTaskId = cancelled.id
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { cancelledTaskId = nil }
            }
        }) { activity in
            CompleteTaskView(activity: activity) {
                lastPhotoTask = nil   // clear so onDismiss knows it succeeded
                vm.markDoneLocally(activity)
                Task { await vm.loadActivities() }
            }
        }
    }

    // MARK: Actions

    private func completeTask(_ activity: Activity) {
        if requirePhoto {
            // Don't mark done yet — wait for photo submission
            lastPhotoTask = activity
            taskToComplete = activity
        } else if activity.frequency != .once {
            vm.markDoneLocally(activity)   // instant feedback
            Task { await vm.markHabitDone(activity) }
        } else {
            vm.markDoneLocally(activity)   // instant feedback
            Task { await vm.markCompleted(activity); await vm.loadActivities() }
        }
    }

    private func reload() { Task { await vm.loadActivities() } }
    private func after(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: action)
    }
}

// MARK: - Top bar (glow + fade; cards scroll underneath and dissolve)

private struct HomeTopBar: View {
    let dateLabel: String
    let count: Int
    let allDone: Bool
    let streak: Int

    var body: some View {
        HomeHeader(dateLabel: dateLabel, count: count, allDone: allDone, streak: streak)
            .appearEffect(delay: 0.05)
            .frame(maxWidth: .infinity)
            .background {
                ZStack {
                    AppColors.background
                    Ellipse()
                        .fill(AppColors.headerBlue)
                        .frame(width: 540, height: 320)
                        .blur(radius: 80)
                        .offset(y: -150)
                }
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black, location: 0.6),
                            .init(color: .black.opacity(0), location: 1.0)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .ignoresSafeArea(edges: .top)
            }
    }
}

// MARK: - Header

private struct HomeHeader: View {
    let dateLabel: String
    let count: Int
    let allDone: Bool
    let streak: Int

    private var flameColor: Color {
        if allDone { return .red }
        if streak > 0 { return .orange }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("Today,")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(dateLabel)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(minWidth: 26, minHeight: 26)
                    .padding(.horizontal, 4)
                    .background(Circle().fill(AppColors.challengeLabel))
            }

            HStack(spacing: 3) {
                Image(systemName: streak > 0 ? "flame.fill" : "flame")
                    .font(.system(size: 19, weight: .semibold))
                Text("\(streak)")
                    .font(.system(size: 19, weight: .bold))
            }
            .foregroundStyle(flameColor)
        }
        .padding(.top, 16)
        .padding(.bottom, 18)
    }
}

// MARK: - Empty state

private struct EmptyTodayView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("✨").font(.system(size: 48))
            Text("All clear for today")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Add a task with the buttons below")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Task card

private struct TaskCardView: View {
    let task: Activity
    let subtasks: [Activity]
    let isDone: (Activity) -> Bool
    let onOpen: () -> Void
    let onToggle: (Activity) -> Void
    let onEdit: (Activity) -> Void
    let onDelete: (Activity) -> Void
    let onTomorrow: (Activity) -> Void
    var cancelledTaskId: UUID? = nil

    @State private var isCompleting = false

    private var accent: Color { typeAccent(task.type) }
    private var isGoal: Bool { task.goalTarget != nil && task.goalTarget! > 0 }

    private var subtitle: String? {
        if let target = task.goalTarget, target > 0 {
            return "\(grouped(task.goalProgress)) / \(grouped(target))"
        }
        if task.type.hasStreak && task.streakCurrent > 0 {
            return "🔥 \(task.streakCurrent)"
        }
        return nil
    }

    private var ringToggle: (() -> Void)? {
        if isGoal { return nil }
        return { handleToggle() }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack(spacing: 14) {
                Image(systemName: task.type.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(task.title)
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.primary)
                        .strikethrough(isCompleting, color: .primary)
                        .lineLimit(1)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                TaskRing(
                    accent: accent,
                    icon: task.type.icon,
                    isGoal: isGoal,
                    progress: task.progressFraction,
                    isChecked: isCompleting,
                    onToggle: ringToggle
                )
            }

            if !subtasks.isEmpty {
                VStack(spacing: 12) {
                    ForEach(subtasks) { sub in
                        SubTaskRow(subtask: sub, accent: typeAccent(sub.type), onToggle: onToggle)
                    }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppColors.cardBg)
        )
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture { Haptics.selection(); onOpen() }
        .contextMenu {
            Button { onEdit(task) } label: { Label("Изменить", systemImage: "pencil") }
            Button { onTomorrow(task) } label: { Label("На завтра", systemImage: "calendar") }
            Button(role: .destructive) { onDelete(task) } label: { Label("Удалить", systemImage: "trash") }
        }
        .onChange(of: cancelledTaskId) { _, id in
            if id == task.id, isCompleting {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isCompleting = false }
            }
        }
        .swipeToDelete { onDelete(task) }
    }

    private func handleToggle() {
        guard !isCompleting else { return }
        Haptics.medium()
        withAnimation { isCompleting = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { onToggle(task) }
    }
}

// MARK: - Ring

private struct TaskRing: View {
    let accent: Color
    let icon: String
    let isGoal: Bool
    let progress: Double
    let isChecked: Bool
    /// nil = display-only (goal progress); otherwise tap completes the task.
    let onToggle: (() -> Void)?

    var body: some View {
        if isGoal {
            ZStack {
                Circle().stroke(accent.opacity(0.2), lineWidth: 5)
                Circle().trim(from: 0, to: max(0.001, progress))
                    .stroke(accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(accent)
            }
            .frame(width: 48, height: 48)
        } else {
            Button { onToggle?() } label: {
                ZStack {
                    Circle()
                        .fill(isChecked ? accent : Color.clear)
                        .overlay(
                            Circle().strokeBorder(
                                isChecked ? Color.clear : Color.secondary.opacity(0.4),
                                style: StrokeStyle(lineWidth: 2.5, dash: isChecked ? [] : [5])
                            )
                        )
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(isChecked ? .white : Color.secondary.opacity(0.5))
                }
                .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isChecked)
        }
    }
}

// MARK: - Subtask row

private struct SubTaskRow: View {
    let subtask: Activity
    let accent: Color
    let onToggle: (Activity) -> Void
    @State private var isCompleting = false

    var body: some View {
        HStack(spacing: 14) {
            Text(subtask.title)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(.primary)
                .strikethrough(isCompleting, color: .primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            TaskRing(
                accent: accent, icon: subtask.type.icon, isGoal: false,
                progress: 0, isChecked: isCompleting, onToggle: handleToggle
            )
            .scaleEffect(0.82)
        }
        .padding(.leading, 44)
    }

    private func handleToggle() {
        guard !isCompleting else { return }
        Haptics.medium()
        withAnimation { isCompleting = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { onToggle(subtask) }
    }
}

// MARK: - Bottom buttons

private struct BottomButtons: View {
    let onSettings: () -> Void
    let onAI: () -> Void
    let onPlus: () -> Void

    var body: some View {
        HStack {
            // Wide pill: settings (left) + AI (right)
            ZStack {
                RoundedRectangle(cornerRadius: 1000)
                    .fill(AppColors.buttonBg)
                    .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                HStack(spacing: 0) {
                    Button(action: onSettings) {
                        Image(systemName: "gearshape")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    Rectangle()
                        .fill(AppColors.separatorLine)
                        .frame(width: 1, height: AppSpacing.buttonSize * 0.75)
                    Button(action: onAI) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 22, weight: .heavy))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .frame(width: AppSpacing.wideButtonWidth, height: AppSpacing.buttonSize)

            Spacer()

            // Plus button → create popup
            Button(action: onPlus) {
                ZStack {
                    Circle()
                        .fill(AppColors.buttonBg)
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .heavy))
                        .foregroundStyle(.primary)
                }
                .frame(width: AppSpacing.buttonSize, height: AppSpacing.buttonSize)
            }
            .buttonStyle(.haptic)
        }
        .padding(.horizontal, 22)
    }
}

#Preview {
    HomeView()
        .environment(AuthService.shared)
}
