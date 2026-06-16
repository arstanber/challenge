import SwiftUI
import UniformTypeIdentifiers

// MARK: - Inline reorder drop delegate
// Live-reorders myActivities as a dragged card passes over a target, then
// persists sort_order when the drop completes.
private struct TaskReorderDropDelegate: DropDelegate {
    let item: Activity
    let vm: ActivitiesViewModel
    @Binding var dragging: Activity?

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging.id != item.id else { return }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            vm.moveActivity(dragging, before: item)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        dragging = nil
        Task { await vm.persistOrder() }
        return true
    }
}

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

// MARK: - Strict mode

/// Refusal details when strict mode blocks completion: a connected data
/// source reports today's value below the task's goal.
private struct StrictBlock: Identifiable {
    let id = UUID()
    let title: String
    let current: Double
    let target: Double

    /// "6 500 из 10 000" -- one decimal for small (distance-like) values.
    var progressText: String {
        func num(_ v: Double) -> String {
            let f = NumberFormatter()
            f.numberStyle = .decimal
            f.groupingSeparator = " "
            f.maximumFractionDigits = v < 100 ? 1 : 0
            return f.string(from: NSNumber(value: v)) ?? "\(Int(v))"
        }
        return "\(num(current)) из \(num(target))"
    }
}

// MARK: - Home

struct HomeView: View {
    @State private var vm = ActivitiesViewModel()
    @AppStorage("requirePhotoVerification") private var requirePhoto = true
    // ON: done tasks collect struck-through at the bottom. OFF: they stay
    // in place in the list order.
    @AppStorage(AppPrefs.Key.groupCompleted) private var groupCompleted = true
    @AppStorage(AppPrefs.Key.strictMode) private var strictMode = true
    @AppStorage(AppPrefs.Key.zoomerMode) private var zoomerMode = false
    // Strict-mode refusal: connector says the goal is not reached yet.
    @State private var strictBlock: StrictBlock?

    // Creation
    @State private var showAIPlanner = false
    @State private var showBySaying = false
    @State private var showByYourself = false
    @State private var showAddHabit = false
    @State private var newHabitDraft: HabitDraft?
    // Navigation
    @State private var showSettings = false
    // Inline drag-to-reorder happens right on the home list (no separate page).
    @State private var reorderMode = false
    @State private var draggingTask: Activity?
    // Task interaction
    @State private var taskToComplete: Activity?
    @State private var lastPhotoTask: Activity?
    @State private var cancelledTaskId: UUID?
    @State private var editingActivity: Activity?
    @State private var detailActivity: Activity?
    @State private var deletingActivity: Activity?
    @State private var addSubtaskParent: Activity?
    // Celebration
    @State private var confettiTrigger = 0
    @State private var showPerfectDay = false
    // Activation: first-win card until the first photo report lands.
    // hasSubmittedFirstReport is set by ActivityDetailViewModel on the first
    // verdict and backfilled by TaskEngine for accounts with streak history.
    @AppStorage("hasSubmittedFirstReport") private var hasSubmittedFirstReport = false
    @AppStorage("firstWinCardDismissed") private var firstWinCardDismissed = false
    // Connector suggestions (queued by creation flows, presented here)
    @State private var suggestionEngine = ConnectorSuggestionEngine.shared
    @State private var connectorSuggestion: ConnectorSuggestionEngine.Suggestion?
    // Bumped exactly at 00:00 (NSCalendarDayChanged) so the date label and
    // the today/upcoming buckets recompute without an app restart.
    @State private var today = Date()

    // iPad (regular width) lays task cards out in a width-adaptive grid:
    // ~2 columns in portrait, ~3 in landscape, chosen from the available width.
    @Environment(\.horizontalSizeClass) private var hSize
    private var isWide: Bool { hSize == .regular }
    private var taskColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 330, maximum: 540), spacing: 14)]
    }
    // Wider reading column on iPad so landscape fills more of the screen while
    // portrait still stays a comfortable two-up.
    private var contentMaxWidth: CGFloat { isWide ? 1100 : 640 }

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
        let endOfToday = cal.date(bySettingHour: 23, minute: 59, second: 59, of: today)!
        return activeTasks.filter { a in
            guard isTopLevel(a) else { return false }
            if a.type == .goal, activeTasks.contains(where: { $0.parentId == a.id }) { return true }
            if a.frequency == .once {
                guard let d = a.deadline else { return true }
                return d <= endOfToday
            }
            // Recurring: only on scheduled weekdays; deadline is an expiry
            // date ("repeat until"), not a due date.
            guard a.isScheduled(on: today) else { return false }
            if let d = a.deadline, d < today { return false }
            return true
        }
    }

    private var upcomingTasks: [Activity] {
        let cal = Calendar.current
        let endOfToday = cal.date(bySettingHour: 23, minute: 59, second: 59, of: today)!
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

    /// Top-level tasks already handled today -- shown struck-through at the
    /// bottom of the list instead of disappearing.
    private var doneTodayTasks: [Activity] {
        (vm.myActivities + vm.parentActivities)
            .filter { $0.parentId == nil }
            .filter { vm.isHandledToday($0.id) }
    }

    /// Main list rows: pending tasks, with done ones interleaved in their
    /// original positions when "Группировать выполненные" is off.
    private var mainRows: [(task: Activity, isDone: Bool)] {
        if groupCompleted { return todayTasks.map { ($0, false) } }
        let pendingIds = Set(todayTasks.map(\.id))
        let doneIds = Set(doneTodayTasks.map(\.id))
        return (vm.myActivities + vm.parentActivities).compactMap { a in
            if pendingIds.contains(a.id) { return (a, false) }
            if doneIds.contains(a.id) { return (a, true) }
            return nil
        }
    }

    /// Done tasks rendered as the bottom group (grouped mode only).
    private var bottomDoneTasks: [Activity] {
        groupCompleted ? doneTodayTasks : []
    }

    // MARK: Card builders (shared by the stacked iPhone list and the iPad grid)

    @ViewBuilder private var mainCards: some View {
        ForEach(Array(mainRows.enumerated()), id: \.element.task.id) { idx, row in
            if row.isDone {
                DoneTaskCard(task: row.task,
                             onOpen: { detailActivity = row.task },
                             onUndo: { Task { await vm.undoHabitToday(row.task) } })
                    .appearEffect(delay: 0.1 + Double(idx) * 0.05)
            } else {
                taskCard(row.task)
                    .appearEffect(delay: 0.1 + Double(idx) * 0.05)
            }
        }
    }

    @ViewBuilder private var upcomingCards: some View {
        ForEach(Array(upcomingTasks.enumerated()), id: \.element.id) { idx, task in
            taskCard(task)
                .appearEffect(delay: 0.16 + Double(idx) * 0.05)
        }
    }

    @ViewBuilder private var doneCards: some View {
        ForEach(Array(bottomDoneTasks.enumerated()), id: \.element.id) { idx, task in
            DoneTaskCard(task: task,
                         onOpen: { detailActivity = task },
                         onUndo: { Task { await vm.undoHabitToday(task) } })
                .appearEffect(delay: 0.2 + Double(idx) * 0.05)
        }
    }

    @ViewBuilder private func taskCard(_ task: Activity) -> some View {
        TaskCardView(
            task: task,
            subtasks: pendingSubtasks(of: task),
            isDone: { vm.isDoneToday($0.id) },
            onOpen: { detailActivity = task },
            onToggle: completeTask,
            onEdit: { editingActivity = $0 },
            onDelete: { act in deletingActivity = act },
            onTomorrow: { act in Task { await vm.moveToTomorrow(act); await vm.loadActivities() } },
            onAddSubtask: { addSubtaskParent = $0 },
            reordering: reorderMode,
            cancelledTaskId: cancelledTaskId
        )
        .opacity(reorderMode && draggingTask?.id == task.id ? 0.5 : 1)
        // Inline drag-to-reorder: only armed while in reorder mode.
        .if(reorderMode) { view in
            view
                .onDrag {
                    draggingTask = task
                    return NSItemProvider(object: task.id.uuidString as NSString)
                }
                .onDrop(of: [.text], delegate: TaskReorderDropDelegate(
                    item: task, vm: vm, dragging: $draggingTask))
        }
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
        return f.string(from: today)
    }

    // MARK: Body

    var body: some View {
        ZStack(alignment: .top) {
            AppColors.background.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 14) {
                    if !hasSubmittedFirstReport && !firstWinCardDismissed {
                        FirstWinCard(
                            onAccept: acceptFirstWin,
                            onDismiss: { Haptics.tap(); firstWinCardDismissed = true }
                        )
                        .appearEffect(delay: 0.05)
                        .onAppear(perform: trackFirstWinShownOnce)
                    }

                    // Only offer a freeze when the streak is actually broken
                    // (current == 0). If today already counts, the run isn't
                    // interrupted, so "Серия прервалась?" would be misleading.
                    if vm.globalStreakCurrent == 0 && vm.yesterdayFreezable && vm.freezesAvailable > 0 {
                        FreezeYesterdayBanner(remaining: vm.freezesAvailable) {
                            Haptics.medium()
                            Task {
                                await vm.freezeYesterday()
                                confettiTrigger += 1
                                Haptics.success()
                            }
                        }
                        .appearEffect(delay: 0.05)
                    }

                    if vm.isLoading && activeTasks.isEmpty && doneTodayTasks.isEmpty {
                        SkeletonTaskList(rows: 4)
                            .padding(.top, 8)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    } else if todayTasks.isEmpty && upcomingTasks.isEmpty && doneTodayTasks.isEmpty {
                        EmptyTodayView()
                            .padding(.top, 40)
                    } else {
                        if isWide {
                            LazyVGrid(columns: taskColumns, alignment: .leading, spacing: 14) {
                                mainCards
                            }
                        } else {
                            mainCards
                        }

                        if !upcomingTasks.isEmpty {
                            Text("Скоро")
                                .font(.sfProDisplay(13, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 4)
                                .padding(.top, 6)

                            if isWide {
                                LazyVGrid(columns: taskColumns, alignment: .leading, spacing: 14) {
                                    upcomingCards
                                }
                            } else {
                                upcomingCards
                            }
                        }

                        // Done today -- struck through at the bottom (grouped mode)
                        if isWide {
                            LazyVGrid(columns: taskColumns, alignment: .leading, spacing: 14) {
                                doneCards
                            }
                        } else {
                            doneCards
                        }
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 84)
                .padding(.bottom, 20)
                .readableWidth(contentMaxWidth)
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HomeTopBar(dateLabel: todayLabel, count: todayTasks.count,
                           allDone: allDone, streak: vm.globalStreakCurrent)
            }

            ConfettiView(trigger: confettiTrigger)
                .ignoresSafeArea().zIndex(20).allowsHitTesting(false)
        }
        // "reInspire." tucked under the Dynamic Island
        .overlay(alignment: .top) {
            Text("reInspire.")
                .font(.sfProDisplay(16, weight: .semibold))
                .foregroundStyle(.primary)
                .padding(.top, 14)
                .ignoresSafeArea(.container, edges: .top)
        }
        // Bottom create buttons, always above the home indicator
        .safeAreaInset(edge: .bottom) {
            BottomButtons(
                onSettings: { Haptics.tap(); showSettings = true },
                onReorder: {
                    Haptics.medium()
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        reorderMode.toggle()
                    }
                    if !reorderMode { Task { await vm.persistOrder() } }
                },
                reordering: reorderMode,
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
            vm.startSyncObserver()
            await vm.loadActivities()
            NotificationService.shared.clearLegacyMotivationPlan()
            await syncAllNotifications()
        }
        // Pending pushes carry the tone they were scheduled with, so flipping
        // zoomer mode must rebuild them all to take effect before next launch.
        .onChange(of: zoomerMode) {
            Task { await syncAllNotifications() }
        }
        // Keep the evening push numbers honest as tasks get completed during
        // the day (also cancels both nudges once the 75% goal is met).
        .onChange(of: vm.todayDoneTopLevelCount) { _, done in
            NotificationService.shared.scheduleStreakNudge(
                streak: vm.globalStreakCurrent,
                tasksToSave: max(0, vm.dailyStreakGoal - done)
            )
        }
        // Rollover exactly at 00:00 (also posted on resume when the day
        // changed while suspended): reset day-scoped state and re-render.
        .task {
            let dayChanges = NotificationCenter.default
                .notifications(named: .NSCalendarDayChanged)
                .map { _ in () }
            for await _ in dayChanges {
                today = Date()
                await TaskEngine.shared.handleDayChange()
                await vm.loadActivities()
            }
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
                onAIStepByStep: {
                    showAddHabit = false
                    after { showAIPlanner = true }
                },
                onBySaying: {
                    showAddHabit = false
                    after { showBySaying = true }
                },
                onByYourself: {
                    showAddHabit = false
                    after { showByYourself = true }
                }
            )
        }
        .fullScreenCover(isPresented: $showByYourself, onDismiss: reload) {
            ByYourselfView()
        }
        .sheet(item: $newHabitDraft, onDismiss: reload) { draft in
            NewHabitView(draft: draft, vm: vm) { Task { await vm.loadActivities() } }
        }
        .sheet(isPresented: $showAIPlanner, onDismiss: reload) { GoalPlannerView() }
        .sheet(item: $connectorSuggestion, onDismiss: { suggestionEngine.dismissPending() }) { suggestion in
            ConnectorSuggestionSheet(suggestion: suggestion)
        }
        .onChange(of: suggestionEngine.pending) { _, newValue in
            // Creation usually happens inside another sheet; wait out its
            // dismissal animation before presenting ours.
            if newValue != nil { presentConnectorSuggestion(delay: 1.0) }
        }
        .sheet(isPresented: $showBySaying, onDismiss: reload) { BySayingView() }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(item: $addSubtaskParent) { parent in
            AddSubtaskSheet(parent: parent, vm: vm, onCreated: reload)
        }
        .alert(
            "Строгий режим",
            isPresented: .init(get: { strictBlock != nil }, set: { if !$0 { strictBlock = nil } }),
            presenting: strictBlock
        ) { _ in
            Button("Понятно", role: .cancel) { strictBlock = nil }
        } message: { block in
            Text("«\(block.title)»: цель пока не достигнута -- \(block.progressText) по данным приложений. Завершите цель полностью или отключите строгий режим в настройках.")
        }
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
        .alert("Ошибка", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { Haptics.tap(); vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    // MARK: Actions

    private func completeTask(_ activity: Activity) {
        Task {
            if strictMode, let block = await strictModeBlock(for: activity) {
                Haptics.warning()
                strictBlock = block
                return
            }
            proceedWithCompletion(activity)
        }
    }

    /// Strict mode: when a connected data source reports today's value below
    /// the task's goal, completion is refused with an explanation. Tasks
    /// without a goal or without connector data are never blocked.
    private func strictModeBlock(for activity: Activity) async -> StrictBlock? {
        guard let target = activity.goalTarget, target > 0 else { return nil }
        guard let current = await ConnectorService.shared.todayValue(for: activity),
              current < target else { return nil }
        return StrictBlock(title: activity.title, current: current, target: target)
    }

    private func proceedWithCompletion(_ activity: Activity) {
        if requirePhoto && activity.type.requiresPhoto {
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

    /// Creates the starter challenge and drops the user straight into the
    /// camera flow -- the goal is a first AI verdict in this very session.
    private func acceptFirstWin() {
        Haptics.tap()
        AnalyticsService.shared.track(.firstWinAccepted)
        Task {
            guard let activity = await vm.createActivity(
                title: "Выпить стакан воды",
                type: .challenge,
                frequency: .once,
                condition: "На фото человек пьёт воду или держит стакан/бутылку с водой"
            ) else { return }
            lastPhotoTask = activity
            taskToComplete = activity
        }
    }

    private func trackFirstWinShownOnce() {
        let key = "firstWinShownTracked"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        AnalyticsService.shared.track(.firstWinShown)
    }

    private func reload() {
        Task { await vm.loadActivities() }
        presentConnectorSuggestion(delay: 0.6)
    }

    /// (Re-)schedules every local push from the current vm state: per-task
    /// reminders, streak-risk nudges, weekly review and the personal-time
    /// nudge. Runs on appear and again whenever zoomer mode flips.
    private func syncAllNotifications() async {
        let notifications = NotificationService.shared
        notifications.syncReminders(for: vm.myActivities + vm.parentActivities)
        notifications.scheduleStreakNudge(
            streak: vm.globalStreakCurrent,
            tasksToSave: max(0, vm.dailyStreakGoal - vm.todayDoneTopLevelCount)
        )
        notifications.scheduleWeeklyReview()
        let minute = await TaskEngine.shared.typicalCompletionMinute()
        // A touch before the habitual time, so the push lands while the
        // usual completion window is still open.
        notifications.schedulePersonalNudge(
            minuteOfDay: minute.map { $0 - 15 },
            streak: vm.globalStreakCurrent
        )
    }
    private func after(_ action: @escaping () -> Void) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: action)
    }
    /// Presents the queued connector suggestion once no other sheet is in the way.
    private func presentConnectorSuggestion(delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            guard connectorSuggestion == nil, let pending = suggestionEngine.pending else { return }
            connectorSuggestion = pending
        }
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
    @State private var flamePulse = false

    private var flameColor: Color {
        if allDone { return Color(hex: "FF6A00") }   // vivid orange, not red
        if streak > 0 { return .orange }
        return .secondary
    }

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Text("Сегодня,")
                    .font(.sfProDisplay(24, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(dateLabel)
                    .font(.sfProDisplay(24, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            if count > 0 {
                Text("\(count)")
                    .font(.sfProDisplay(14, weight: .bold))
                    .foregroundColor(.white)
                    .frame(minWidth: 26, minHeight: 26)
                    .padding(.horizontal, 4)
                    .background(Circle().fill(AppColors.challengeLabel))
                    .contentTransition(.numericText())
                    .transition(.scale.combined(with: .opacity))
            }

            HStack(spacing: 3) {
                Image(systemName: streak > 0 ? "flame.fill" : "flame")
                    .font(.system(size: 19, weight: .semibold))
                    .symbolEffect(.bounce, value: streak)
                    .scaleEffect(allDone && flamePulse ? 1.12 : 1.0)
                Text("\(streak)")
                    .font(.sfProDisplay(19, weight: .bold))
                    .contentTransition(.numericText())
            }
            .foregroundStyle(flameColor)
            .onChange(of: allDone) { _, done in
                guard done else { flamePulse = false; return }
                withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                    flamePulse = true
                }
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 18)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: count)
        .animation(.spring(response: 0.4, dampingFraction: 0.7), value: streak)
    }
}

// MARK: - Empty state

private struct EmptyTodayView: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("✨").font(.system(size: 48))
            Text("На сегодня всё")
                .font(.sfProDisplay(18, weight: .semibold))
                .foregroundStyle(.primary)
            Text("Добавьте задачу кнопками ниже")
                .font(.sfProDisplay(14, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Freeze yesterday banner

private struct FreezeYesterdayBanner: View {
    let remaining: Int
    let onFreeze: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text("🧊").font(.system(size: 30))
            VStack(alignment: .leading, spacing: 3) {
                Text("Серия прервалась?")
                    .font(.sfProDisplay(16, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Заморозь вчерашний день -- осталось \(remaining)")
                    .font(.sfProDisplay(13, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button(action: onFreeze) {
                Text("Заморозить")
                    .font(.sfProDisplay(14, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(Capsule().fill(Color(hex: "4580FF")))
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(hex: "4580FF").opacity(0.12))
        )
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
    var onAddSubtask: ((Activity) -> Void)? = nil
    var reordering: Bool = false
    var cancelledTaskId: UUID? = nil

    @State private var isCompleting = false
    @State private var isPressed = false
    @State private var wiggle = false

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
                        .font(.sfProDisplay(19, weight: .semibold))
                        .foregroundStyle(.primary)
                        .strikethrough(isCompleting, color: .primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if let subtitle {
                        Text(subtitle)
                            .font(.sfProDisplay(14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                if reordering {
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 48, height: 48)
                } else {
                    TaskRing(
                        accent: accent,
                        icon: task.type.icon,
                        isGoal: isGoal,
                        progress: task.progressFraction,
                        isChecked: isCompleting,
                        onToggle: ringToggle
                    )
                }
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
        .scaleEffect(isPressed ? 0.975 : 1.0)
        .rotationEffect(.degrees(reordering && wiggle ? -1.1 : 0))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isPressed)
        // Tap / press / context menu / swipe all fight the drag gesture, so they
        // are completely removed while reordering -- otherwise the lift never
        // starts and the cards won't move.
        .if(!reordering) { view in
            view
                .onTapGesture { Haptics.selection(); onOpen() }
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in isPressed = true }
                        .onEnded { _ in isPressed = false }
                )
                .contextMenu {
                    Button { onEdit(task) } label: { Label("Изменить", systemImage: "pencil") }
                    if isGoal, let onAddSubtask {
                        Button { onAddSubtask(task) } label: { Label("Добавить подзадачу", systemImage: "plus.circle") }
                    }
                    Button { onTomorrow(task) } label: { Label("На завтра", systemImage: "calendar") }
                    Button(role: .destructive) { onDelete(task) } label: { Label("Удалить", systemImage: "trash") }
                }
                .swipeCardActions(
                    onComplete: isGoal ? nil : { handleToggle() },
                    onDelete: { onDelete(task) }
                )
        }
        .onChange(of: cancelledTaskId) { _, id in
            if id == task.id, isCompleting {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { isCompleting = false }
            }
        }
        .onChange(of: reordering) { _, on in
            if on {
                withAnimation(.easeInOut(duration: 0.16).repeatForever(autoreverses: true)) { wiggle = true }
            } else {
                wiggle = false
            }
        }
    }

    private func handleToggle() {
        guard !isCompleting else { return }
        Haptics.medium()
        withAnimation { isCompleting = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { onToggle(task) }
    }
}

// MARK: - Done task card (struck through, bottom of the list)

private struct DoneTaskCard: View {
    let task: Activity
    let onOpen: () -> Void
    var onUndo: () -> Void = {}

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: task.type.icon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary.opacity(0.6))
                .frame(width: 30)

            HStack(spacing: 8) {
                Text(task.title)
                    .font(.sfProDisplay(19, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .strikethrough(true, color: .secondary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if task.type.hasStreak && task.streakCurrent > 0 {
                    Text("🔥\(task.streakCurrent)")
                        .font(.sfProDisplay(14, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Haptics.tap(); onUndo()
            } label: {
                ZStack {
                    Circle().fill(Color(hex: "2FB873"))
                    Image(systemName: "checkmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                }
                .frame(width: 48, height: 48)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppColors.cardBg.opacity(0.45))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .onTapGesture { Haptics.selection(); onOpen() }
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
                        .scaleEffect(isChecked ? 1.0 : 0.6)
                }
                .frame(width: 48, height: 48)
                // Brief overshoot when the task gets checked off.
                .scaleEffect(isChecked ? 1.08 : 1.0)
            }
            .buttonStyle(.plain)
            .animation(.spring(response: 0.34, dampingFraction: 0.55), value: isChecked)
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
                .font(.sfProDisplay(16, weight: .semibold))
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
    let onReorder: () -> Void
    var reordering: Bool = false
    let onPlus: () -> Void

    var body: some View {
        HStack {
            // Wide pill: settings | reorder
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
                    Button(action: onReorder) {
                        Image(systemName: reordering ? "checkmark" : "arrow.up.arrow.down")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(reordering ? Color(hex: "4580FF") : .primary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .background(
                                reordering
                                ? Color(hex: "4580FF").opacity(0.14)
                                : Color.clear
                            )
                    }
                }
            }
            .frame(width: AppSpacing.wideButtonWidth, height: AppSpacing.buttonSize)
            .clipShape(RoundedRectangle(cornerRadius: 1000))

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
        .readableWidth()
    }
}

#Preview {
    HomeView()
        .environment(AuthService.shared)
}
