import SwiftUI

// MARK: - Home section

struct RoutineHomeSection: View {
    let routines: [Routine]
    let activities: [Activity]
    let isHandled: (UUID) -> Bool
    let onStart: (Routine) -> Void
    let onManage: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Рутины")
                    .font(.sfProDisplay(17, weight: .semibold))
                Spacer()
                Button("Настроить", action: onManage)
                    .font(.sfProDisplay(13, weight: .semibold))
                    .foregroundStyle(Color(hex: "4580FF"))
                    .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            if routines.isEmpty {
                Button(action: onManage) {
                    HStack(spacing: 14) {
                        Image(systemName: "rectangle.stack.badge.plus")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color(hex: "4580FF"))
                            .frame(width: 46, height: 46)
                            .background(Color(hex: "4580FF").opacity(0.12), in: Circle())

                        VStack(alignment: .leading, spacing: 3) {
                            Text("Собрать первую рутину")
                                .font(.sfProDisplay(16, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text("Запускай несколько привычек одной кнопкой")
                                .font(.sfProDisplay(13, weight: .regular))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.secondary)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                }
                .buttonStyle(.plain)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(routines) { routine in
                            Button {
                                Haptics.tap()
                                onStart(routine)
                            } label: {
                                routineCard(routine)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .contentMargins(.horizontal, 0, for: .scrollContent)
            }
        }
    }

    private func routineCard(_ routine: Routine) -> some View {
        let steps = routine.activityIds.compactMap { id in
            activities.first { $0.id == id }
        }.filter(isAvailableToday)
        let remaining = steps.filter { !isHandled($0.id) && $0.status == .active }.count
        let completed = max(0, steps.count - remaining)

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: routine.icon)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Color(hex: "4580FF"), in: Circle())
                Spacer()
                Text(routine.period.title)
                    .font(.sfProDisplay(11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(routine.name)
                    .font(.sfProDisplay(17, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(remaining == 0 ? "Готово на сегодня" : "\(remaining) шагов осталось")
                    .font(.sfProDisplay(12, weight: .regular))
                    .foregroundStyle(remaining == 0 ? Color.green : .secondary)
            }

            ProgressView(value: Double(completed), total: Double(max(1, steps.count)))
                .tint(remaining == 0 ? .green : Color(hex: "4580FF"))
        }
        .padding(16)
        .frame(width: 210, height: 142, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func isAvailableToday(_ activity: Activity) -> Bool {
        guard activity.frequency != .once else { return true }
        guard activity.isScheduled(on: Date()) else { return false }
        guard let deadline = activity.deadline else { return true }
        return deadline >= Calendar.current.startOfDay(for: Date())
    }
}

// MARK: - Manager

struct RoutinesView: View {
    let activities: [Activity]
    let isHandled: (UUID) -> Bool
    let onStart: (Routine) -> Void

    @State private var service = RoutineService.shared
    @State private var editorPresented = false
    @State private var editingRoutine: Routine?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if service.isLoading && service.routines.isEmpty {
                    ProgressView()
                } else if service.routines.isEmpty {
                    ContentUnavailableView {
                        Label("Нет рутин", systemImage: "rectangle.stack")
                    } description: {
                        Text("Собери утреннюю или вечернюю последовательность из существующих задач.")
                    } actions: {
                        Button("Создать рутину") {
                            editingRoutine = nil
                            editorPresented = true
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(service.routines) { routine in
                            Button {
                                dismiss()
                                onStart(routine)
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: routine.icon)
                                        .font(.system(size: 19, weight: .semibold))
                                        .foregroundStyle(Color(hex: "4580FF"))
                                        .frame(width: 42, height: 42)
                                        .background(Color(hex: "4580FF").opacity(0.12), in: Circle())

                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(routine.name)
                                            .font(.sfProDisplay(17, weight: .semibold))
                                            .foregroundStyle(.primary)
                                        Text(routineSubtitle(routine))
                                            .font(.sfProDisplay(13, weight: .regular))
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()
                                    Image(systemName: "play.fill")
                                        .foregroundStyle(Color(hex: "4580FF"))
                                }
                            }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                Button {
                                    editingRoutine = routine
                                    editorPresented = true
                                } label: {
                                    Label("Изменить", systemImage: "pencil")
                                }
                                .tint(Color(hex: "4580FF"))
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await service.delete(routine) }
                                } label: {
                                    Label("Удалить", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Рутины")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        editingRoutine = nil
                        editorPresented = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .refreshable { await service.load() }
            .task { await service.load() }
            .sheet(isPresented: $editorPresented) {
                RoutineEditorView(routine: editingRoutine, activities: availableActivities)
            }
            .alert("Ошибка", isPresented: Binding(
                get: { service.errorMessage != nil },
                set: { if !$0 { service.errorMessage = nil } }
            )) {
                Button("OK") { service.errorMessage = nil }
            } message: {
                Text(service.errorMessage ?? "")
            }
        }
    }

    private var availableActivities: [Activity] {
        let active = activities.filter { $0.status == .active }
        let activeParentIds = Set(active.filter { $0.parentId == nil }.map(\.id))
        return active.filter { activity in
            guard let parentId = activity.parentId else { return true }
            return !activeParentIds.contains(parentId)
        }
    }

    private func routineSubtitle(_ routine: Routine) -> String {
        let availableIds = routine.activityIds.filter { id in
            guard let activity = activities.first(where: { $0.id == id }) else { return false }
            guard activity.frequency != .once else { return true }
            guard activity.isScheduled(on: Date()) else { return false }
            guard let deadline = activity.deadline else { return true }
            return deadline >= Calendar.current.startOfDay(for: Date())
        }
        let remaining = availableIds.filter { !isHandled($0) }.count
        if remaining == 0 { return "\(routine.period.title) · готово" }
        return "\(routine.period.title) · \(remaining) из \(availableIds.count) осталось"
    }
}

// MARK: - Editor

private struct RoutineEditorView: View {
    let routine: Routine?
    let activities: [Activity]

    @State private var service = RoutineService.shared
    @State private var name: String
    @State private var period: RoutinePeriod
    @State private var icon: String
    @State private var selectedActivityIds: [UUID]
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss

    private let icons = [
        "sun.max.fill",
        "moon.stars.fill",
        "sparkles",
        "figure.run",
        "book.fill",
        "drop.fill"
    ]

    init(routine: Routine?, activities: [Activity]) {
        self.routine = routine
        self.activities = activities
        _name = State(initialValue: routine?.name ?? "")
        _period = State(initialValue: routine?.period ?? .morning)
        _icon = State(initialValue: routine?.icon ?? RoutinePeriod.morning.defaultIcon)
        _selectedActivityIds = State(initialValue: routine?.activityIds ?? [])
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Название") {
                    TextField("Например, Доброе утро", text: $name)
                        .textInputAutocapitalization(.sentences)
                }

                Section("Когда") {
                    Picker("Период", selection: $period) {
                        ForEach(RoutinePeriod.allCases) { period in
                            Text(period.title).tag(period)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Иконка") {
                    HStack {
                        ForEach(icons, id: \.self) { symbol in
                            Button {
                                Haptics.selection()
                                icon = symbol
                            } label: {
                                Image(systemName: symbol)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(icon == symbol ? .white : Color(hex: "4580FF"))
                                    .frame(width: 42, height: 42)
                                    .background(
                                        icon == symbol
                                            ? Color(hex: "4580FF")
                                            : Color(hex: "4580FF").opacity(0.10),
                                        in: Circle()
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }

                if !selectedActivityIds.isEmpty {
                    Section("Порядок шагов") {
                        ForEach(selectedActivityIds, id: \.self) { id in
                            if let activity = activity(id) {
                                HStack(spacing: 12) {
                                    Image(systemName: activity.effectiveCompletionMode.icon)
                                        .foregroundStyle(Color(hex: "4580FF"))
                                        .frame(width: 24)
                                    Text(activity.title)
                                    Spacer()
                                    Button {
                                        selectedActivityIds.removeAll { $0 == id }
                                    } label: {
                                        Image(systemName: "minus.circle.fill")
                                            .foregroundStyle(.secondary)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .onMove { source, destination in
                            selectedActivityIds.move(fromOffsets: source, toOffset: destination)
                        }
                    }
                }

                Section("Добавить задачи") {
                    ForEach(unselectedActivities) { activity in
                        Button {
                            guard selectedActivityIds.count < 20 else { return }
                            Haptics.selection()
                            selectedActivityIds.append(activity.id)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: activity.effectiveCompletionMode.icon)
                                    .foregroundStyle(Color(hex: "4580FF"))
                                    .frame(width: 24)
                                Text(activity.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: "plus.circle")
                                    .foregroundStyle(Color(hex: "4580FF"))
                            }
                        }
                    }

                    if unselectedActivities.isEmpty && selectedActivityIds.isEmpty {
                        Text("Сначала создай хотя бы одну активную задачу.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle(routine == nil ? "Новая рутина" : "Изменить рутину")
            .environment(\.editMode, .constant(.active))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        save()
                    } label: {
                        if isSaving {
                            ProgressView()
                        } else {
                            Text("Сохранить")
                        }
                    }
                    .disabled(!canSave || isSaving)
                }
            }
            .onChange(of: period) { oldValue, newValue in
                if icon == oldValue.defaultIcon {
                    icon = newValue.defaultIcon
                }
            }
        }
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !selectedActivityIds.isEmpty
    }

    private var unselectedActivities: [Activity] {
        activities.filter { !selectedActivityIds.contains($0.id) }
    }

    private func activity(_ id: UUID) -> Activity? {
        activities.first { $0.id == id }
    }

    private func save() {
        isSaving = true
        Task {
            let saved = await service.save(
                id: routine?.id ?? UUID(),
                name: name,
                icon: icon,
                period: period,
                activityIds: selectedActivityIds
            )
            isSaving = false
            if saved { dismiss() }
        }
    }
}

// MARK: - Player

struct RoutinePlayerView: View {
    let routine: Routine
    let onChanged: () -> Void

    @State private var vm = ActivitiesViewModel()
    @State private var timerService = ActivityTimerService.shared
    @State private var currentIndex = 0
    @State private var isSubmitting = false
    @State private var cameraActivity: Activity?
    @State private var hasPrepared = false
    @AppStorage("requirePhotoVerification") private var requirePhoto = true
    @Environment(\.dismiss) private var dismiss

    private var orderedActivities: [Activity] {
        let all = vm.myActivities + vm.parentActivities
        return routine.activityIds.compactMap { id in
            all.first { $0.id == id }
        }.filter(isAvailableToday)
    }

    private var currentActivity: Activity? {
        guard orderedActivities.indices.contains(currentIndex) else { return nil }
        return orderedActivities[currentIndex]
    }

    private var finished: Bool {
        hasPrepared && currentActivity == nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemBackground).ignoresSafeArea()

                if vm.isLoading && !hasPrepared {
                    ProgressView()
                } else if finished {
                    completionView
                } else if let activity = currentActivity {
                    stepView(activity)
                } else {
                    ContentUnavailableView(
                        "Нет доступных шагов",
                        systemImage: "rectangle.stack",
                        description: Text("Задачи этой рутины удалены или завершены.")
                    )
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                }
            }
        }
        .task {
            await vm.loadActivities()
            timerService.restoreLiveActivity()
            hasPrepared = true
            advancePastHandled()
        }
        .fullScreenCover(item: $cameraActivity) { activity in
            CompleteTaskView(activity: activity) {
                vm.markDoneLocally(activity)
                Task {
                    await vm.loadActivities()
                    onChanged()
                    advance()
                }
            }
        }
        .alert("Ошибка", isPresented: Binding(
            get: { vm.errorMessage != nil },
            set: { if !$0 { vm.errorMessage = nil } }
        )) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }

    private func stepView(_ activity: Activity) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text(routine.name)
                    .font(.sfProDisplay(15, weight: .semibold))
                    .foregroundStyle(.secondary)
                ProgressView(
                    value: Double(currentIndex),
                    total: Double(max(1, orderedActivities.count))
                )
                .tint(Color(hex: "4580FF"))
                Text("Шаг \(currentIndex + 1) из \(orderedActivities.count)")
                    .font(.sfProDisplay(12, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 28)
            .padding(.top, 18)

            Spacer()

            VStack(spacing: 18) {
                Image(systemName: activity.effectiveCompletionMode.icon)
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 76, height: 76)
                    .background(Color(hex: "4580FF"), in: Circle())

                Text(activity.title)
                    .font(.sfProDisplay(30, weight: .semibold))
                    .multilineTextAlignment(.center)

                if let target = activity.goalTarget, target > 0 {
                    Text(progressText(activity, target: target))
                        .font(.sfProDisplay(16, weight: .semibold))
                        .foregroundStyle(.secondary)
                } else if !activity.description.isEmpty {
                    Text(activity.description)
                        .font(.sfProDisplay(15, weight: .regular))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }

                actionControls(activity)
            }
            .padding(.horizontal, 28)

            Spacer()

            VStack(spacing: 6) {
                Button("Пропустить") {
                    Haptics.tap()
                    advance()
                }
                .disabled(timerService.isActive(activity.id))
                if timerService.isActive(activity.id) {
                    Text("Сначала зачти или сбрось таймер")
                        .font(.sfProDisplay(12, weight: .regular))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.sfProDisplay(15, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.bottom, 32)
        }
    }

    @ViewBuilder
    private func actionControls(_ activity: Activity) -> some View {
        if requirePhoto {
            Button {
                completeCheck(activity)
            } label: {
                Label(
                    "Сделать фото",
                    systemImage: "camera.fill"
                )
                .font(.sfProDisplay(17, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 54)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: "4580FF"))
            .disabled(isSubmitting)
        } else {
            switch activity.effectiveCompletionMode {
            case .counter:
                HStack(spacing: 12) {
                    progressButton("+1", activity: activity, value: 1)
                    progressButton("+5", activity: activity, value: 5)
                }

            case .timer:
                timerControls(activity)

            case .check, .abstinence:
                Button {
                    completeCheck(activity)
                } label: {
                    Label("Выполнено", systemImage: "checkmark")
                        .font(.sfProDisplay(17, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "4580FF"))
                .disabled(isSubmitting)
            }
        }
    }

    private func progressButton(_ title: String, activity: Activity, value: Double) -> some View {
        Button {
            recordProgress(activity, value: value)
        } label: {
            Text(title)
                .font(.sfProDisplay(18, weight: .semibold))
                .frame(width: 110, height: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(Color(hex: "4580FF"))
        .disabled(isSubmitting)
    }

    private func timerControls(_ activity: Activity) -> some View {
        VStack(spacing: 12) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(timerText(activity.id, at: context.date))
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .monospacedDigit()
            }

            HStack(spacing: 12) {
                Button {
                    Haptics.tap()
                    if !timerService.toggle(activity) { Haptics.warning() }
                } label: {
                    Label(
                        timerService.isRunning(activity.id)
                            ? "Пауза"
                            : (timerService.isActive(activity.id) ? "Продолжить" : "Старт"),
                        systemImage: timerService.isRunning(activity.id)
                            ? "pause.fill"
                            : "play.fill"
                    )
                    .frame(minWidth: 100, minHeight: 46)
                }
                .buttonStyle(.borderedProminent)
                .tint(timerService.isRunning(activity.id) ? .orange : Color(hex: "4580FF"))
                .disabled(
                    isSubmitting
                        || timerService.activeActivityId.map { $0 != activity.id } == true
                )

                if timerService.isActive(activity.id)
                    && !timerService.isRunning(activity.id)
                    && timerService.elapsedSeconds(for: activity.id) > 0 {
                    Button("Зачесть") {
                        guard let minutes = timerService.minutesForSubmission(activity.id) else { return }
                        recordTimer(activity, minutes: minutes)
                    }
                    .buttonStyle(.bordered)
                    .tint(Color(hex: "4580FF"))
                    .disabled(isSubmitting)
                }

                if timerService.isActive(activity.id)
                    && !timerService.isRunning(activity.id) {
                    Button("Сбросить", role: .destructive) {
                        Haptics.tap()
                        timerService.reset(activity.id)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSubmitting)
                }
            }

            if timerService.activeActivityId.map({ $0 != activity.id }) == true {
                Text("Уже запущен таймер другой задачи")
                    .font(.sfProDisplay(12, weight: .regular))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var completionView: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 76))
                .foregroundStyle(.green)
            Text("Рутина завершена")
                .font(.sfProDisplay(30, weight: .semibold))
            Text("Все доступные шаги на сегодня пройдены.")
                .font(.sfProDisplay(16, weight: .regular))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            Button("Готово") {
                Haptics.success()
                dismiss()
            }
            .font(.sfProDisplay(17, weight: .semibold))
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .buttonStyle(.borderedProminent)
            .tint(Color(hex: "4580FF"))
            .padding(.horizontal, 28)
            .padding(.bottom, 30)
        }
    }

    private func progressText(_ activity: Activity, target: Double) -> String {
        let unit = activity.effectiveCompletionUnit
        let suffix = unit.isEmpty ? "" : " \(unit)"
        return "\(formatted(activity.goalProgress)) из \(formatted(target))\(suffix)"
    }

    private func formatted(_ value: Double) -> String {
        if value.rounded() == value { return String(Int(value)) }
        return String(format: "%.1f", value)
    }

    private func timerText(_ activityId: UUID, at date: Date) -> String {
        let total = Int(timerService.elapsedSeconds(for: activityId, at: date))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    private func isAvailableToday(_ activity: Activity) -> Bool {
        guard activity.frequency != .once else { return true }
        guard activity.isScheduled(on: Date()) else { return false }
        guard let deadline = activity.deadline else { return true }
        return deadline >= Calendar.current.startOfDay(for: Date())
    }

    private func completeCheck(_ activity: Activity) {
        if requirePhoto {
            cameraActivity = activity
            return
        }

        isSubmitting = true
        Task {
            if activity.frequency == .once {
                await vm.markCompleted(activity)
            } else {
                await vm.markHabitDone(activity)
            }
            await vm.loadActivities()
            isSubmitting = false
            onChanged()
            advance()
        }
    }

    private func recordProgress(_ activity: Activity, value: Double) {
        isSubmitting = true
        Task {
            let recorded = await vm.recordProgress(activity, value: value)
            isSubmitting = false
            guard recorded else { return }
            onChanged()
            advanceIfCompleted(activity.id)
        }
    }

    private func recordTimer(_ activity: Activity, minutes: Double) {
        isSubmitting = true
        Task {
            let recorded = await vm.recordProgress(activity, value: minutes)
            isSubmitting = false
            if recorded {
                timerService.completeSubmission(activity.id)
                onChanged()
                advanceIfCompleted(activity.id)
            } else {
                timerService.cancelSubmission(activity.id)
            }
        }
    }

    private func advanceIfCompleted(_ activityId: UUID) {
        let all = vm.myActivities + vm.parentActivities
        guard let updated = all.first(where: { $0.id == activityId }) else { return }
        let targetReached = updated.goalTarget.map { updated.goalProgress >= $0 } ?? false
        if vm.isHandledToday(activityId) || updated.status == .completed || targetReached {
            advance()
        }
    }

    private func advance() {
        currentIndex += 1
        advancePastHandled()
    }

    private func advancePastHandled() {
        while orderedActivities.indices.contains(currentIndex) {
            let activity = orderedActivities[currentIndex]
            if activity.status == .completed || vm.isHandledToday(activity.id) {
                currentIndex += 1
            } else {
                break
            }
        }
    }
}
