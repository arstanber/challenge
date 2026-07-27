import SwiftUI

// MARK: - Habit Calendar Detail
// Streak header + month calendar + per-task stats + connectable data sources.

struct HabitCalendarView: View {
    @State private var vm: ActivityDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("requirePhotoVerification") private var requirePhoto = true
    @State private var monthOffset = 0
    @State private var showPerfect = false
    @State private var showCamera = false
    @State private var liveToday: Double?
    @State private var shareRequest: ShareRequest?
    @State private var counterValue = ""
    @State private var timerStartedAt: Date?
    @State private var timerAccumulated: TimeInterval = 0

    // Honors the "Начало недели" setting (Mon/Sun-first grid).
    private let cal = AppPrefs.calendar
    private let orange = Color(hex: "FF7A00")
    private let blue = Color(hex: "4580FF")

    init(activity: Activity, onChange: (() -> Void)? = nil) {
        let model = ActivityDetailViewModel(activity: activity)
        model.onReportSubmitted = onChange
        _vm = State(wrappedValue: model)
    }

    // Per-type accent
    private var accent: Color {
        switch vm.activity.type {
        case .challenge:  return Color(hex: "0048E2")
        case .goal:       return Color(hex: "2FB873")
        case .task:       return Color(hex: "FF7A00")
        case .habit:      return Color(hex: "8B5CF6")
        case .assignment: return Color(hex: "EC4899")
        }
    }

    private var isGoal: Bool { (vm.activity.goalTarget ?? 0) > 0 }

    var body: some View {
        ZStack {
            Color(.systemBackground).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 28) {
                    header.appearEffect(delay: 0.05)
                    if needsPhoto { photoRequirementBanner.appearEffect(delay: 0.1) }
                    statsRow.appearEffect(delay: 0.15)
                    monthCalendar.appearEffect(delay: 0.25)
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)
                .padding(.bottom, 170)
                .readableWidth()
            }

            VStack {
                topBar
                Spacer()
                todayBar
                    .readableWidth()
            }
        }
        .task {
            await vm.loadReports()
            await refreshLiveValue()
        }
        .onChange(of: ConnectorService.shared.connected) { _, _ in
            Task { await refreshLiveValue() }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CompleteTaskView(activity: vm.activity) {
                Task { await vm.loadReports() }
                vm.onReportSubmitted?()
                Haptics.success()
                withAnimation { showPerfect = true }
            }
        }
        .overlay {
            if showPerfect {
                PerfectDayView(message: String(localized: "Серия продолжается! 🔥")) { showPerfect = false }
                    .transition(.opacity)
            }
        }
        .sheet(item: $shareRequest) { req in
            ShareComposerView(kind: req.kind, name: req.name)
        }
    }

    // MARK: Top bar

    private var topBar: some View {
        HStack {
            Button { Haptics.tap(); dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary.opacity(0.6))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
            Spacer()
            Button {
                Haptics.tap()
                shareRequest = ShareRequest(
                    kind: .taskDone(title: vm.activity.title,
                                    streak: vm.currentStreak,
                                    connector: vm.activity.connector),
                    name: AuthService.shared.currentUser?.displayLabel)
            } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary.opacity(0.6))
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.primary.opacity(0.08)))
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "flame.fill").foregroundStyle(orange)
                Text("\(vm.currentStreak)-дневная серия")
                    .font(.manrope(.bold, size: 15))
                    .foregroundColor(orange)
            }
            .padding(.top, 30)

            HStack(spacing: 10) {
                Image(systemName: vm.activity.type.icon)
                    .font(.system(size: 26))
                    .foregroundStyle(accent)
                Text(vm.activity.title)
                    .font(.manrope(.extraBold, size: 30))
                    .foregroundColor(.primary)
                    .multilineTextAlignment(.center)
            }
            Text(frequencyLabel)
                .font(.manrope(.medium, size: 15))
                .foregroundColor(.primary.opacity(0.4))
        }
    }

    private var frequencyLabel: String {
        switch vm.activity.frequency {
        case .daily:  return String(localized: "Каждый день")
        case .weekly: return String(localized: "Каждую неделю")
        case .once:   return String(localized: "Один раз")
        case .custom: return String(localized: "По расписанию")
        }
    }

    // MARK: Stats

    private var statsRow: some View {
        HStack(spacing: 0) {
            laurelTile(value: vm.bestStreak, caption: String(localized: "Лучшая серия"))
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1, height: 56)
            statTile(emoji: "📆", value: vm.totalDaysDone, caption: String(localized: "Всего"))
        }
        .padding(.vertical, 8)
    }

    /// Best-streak tile with a golden laurel wreath flanking the number.
    private func laurelTile(value: Int, caption: String) -> some View {
        let gold = Color(hex: "E3B341")
        return VStack(spacing: 4) {
            Text(caption)
                .font(.manrope(.medium, size: 13))
                .foregroundColor(.primary.opacity(0.4))
            HStack(spacing: 4) {
                Image(systemName: "laurel.leading")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(gold)
                Text("\(value)")
                    .font(.manrope(.extraBold, size: 34))
                    .foregroundColor(.primary)
                    .frame(minWidth: 30)
                Image(systemName: "laurel.trailing")
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(gold)
            }
            Text("дней")
                .font(.manrope(.medium, size: 12))
                .foregroundColor(.primary.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
    }

    private func statTile(emoji: String, value: Int, caption: String) -> some View {
        VStack(spacing: 6) {
            Text(caption)
                .font(.manrope(.medium, size: 13))
                .foregroundColor(.primary.opacity(0.4))
            HStack(spacing: 6) {
                Text(emoji).font(.system(size: 18))
                Text("\(value)")
                    .font(.manrope(.extraBold, size: 34))
                    .foregroundColor(.primary)
            }
            Text("дней")
                .font(.manrope(.medium, size: 12))
                .foregroundColor(.primary.opacity(0.4))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Month calendar

    private var monthDate: Date {
        cal.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
    }

    private var monthCalendar: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "calendar").foregroundColor(.primary.opacity(0.5))
                Text(monthTitle)
                    .font(.manrope(.bold, size: 20))
                    .foregroundColor(.primary)
                Spacer()
                Button { Haptics.selection(); withAnimation { monthOffset -= 1 } } label: {
                    Image(systemName: "chevron.left").foregroundColor(.primary.opacity(0.4))
                }
                Button { Haptics.selection(); withAnimation { if monthOffset < 0 { monthOffset += 1 } } } label: {
                    Image(systemName: "chevron.right")
                        .foregroundColor(monthOffset < 0 ? .primary.opacity(0.4) : .primary.opacity(0.15))
                }
                .disabled(monthOffset >= 0)
            }

            // Weekday headers, ordered by the week-start setting
            HStack(spacing: 0) {
                ForEach(AppPrefs.orderedWeekdayLabels, id: \.self) { d in
                    Text(d)
                        .font(.manrope(.medium, size: 13))
                        .foregroundColor(.primary.opacity(0.35))
                        .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.05)))

            // Day grid
            let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
            LazyVGrid(columns: cols, spacing: 10) {
                ForEach(Array(monthCells.enumerated()), id: \.offset) { _, cell in
                    DayCell(cell: cell, done: cell.date.map { vm.completedDays.contains(cal.startOfDay(for: $0)) } ?? false,
                            isToday: cell.date.map { cal.isDateInToday($0) } ?? false,
                            orange: orange, blue: blue)
                }
            }
        }
    }

    private var monthTitle: String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ru_RU"); f.dateFormat = "LLLL"
        return f.string(from: monthDate).capitalized
    }

    /// Cells for the month grid (with leading blanks aligned to the week start).
    private var monthCells: [DayCellModel] {
        guard let interval = cal.dateInterval(of: .month, for: monthDate) else { return [] }
        let firstDay = interval.start
        // weekday 1=Sun..7=Sat → offset from the calendar's first weekday 0..6
        let weekday = cal.component(.weekday, from: firstDay)
        let leading = (weekday - cal.firstWeekday + 7) % 7
        let daysInMonth = cal.range(of: .day, in: .month, for: monthDate)?.count ?? 30

        var cells: [DayCellModel] = []
        for _ in 0..<leading { cells.append(DayCellModel(date: nil, day: nil)) }
        for d in 1...daysInMonth {
            let date = cal.date(byAdding: .day, value: d - 1, to: firstDay)!
            cells.append(DayCellModel(date: date, day: d))
        }
        return cells
    }

    // MARK: Today bar (per-task stat / mark done)

    private var todayBar: some View {
        VStack(spacing: 12) {
            Text("Сегодня")
                .font(.manrope(.bold, size: 16))
                .foregroundColor(.primary)

            if isGoal {
                goalTodayStat
            }

            switch vm.activity.effectiveCompletionMode {
            case .counter:
                counterControl
            case .timer:
                timerControl
            case .check, .abstinence:
                markDoneControl
            }
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        // No bar at all: a tintless progressive blur ramps from sharp (top)
        // to fully blurred (bottom), so content scrolls into soft focus
        // behind the controls without any gray material wash.
        .background {
            VariableBlurView(maxBlurRadius: 16)
                .padding(.top, -50)
                .ignoresSafeArea(edges: .bottom)
                .allowsHitTesting(false)
        }
    }

    private var goalTodayStat: some View {
        let isDistance = ConnectorMetric.infer(from: vm.activity) == .distance
        // Distance goals are stored in km; convert for display when imperial.
        let target = isDistance ? AppPrefs.displayDistance(vm.activity.goalTarget ?? 0)
                                : (vm.activity.goalTarget ?? 0)
        let storedProgress = vm.activity.frequency == .once ? vm.activity.goalProgress : vm.todayProgress
        let rawCurrent = liveToday ?? storedProgress
        let current = isDistance ? AppPrefs.displayDistance(rawCurrent) : rawCurrent
        let unitSuffix = isDistance
            ? " \(AppPrefs.distanceUnit)"
            : (vm.activity.effectiveCompletionUnit.isEmpty ? "" : " \(vm.activity.effectiveCompletionUnit)")
        let fraction = target > 0 ? min(current / target, 1.0) : 0
        return HStack(spacing: 16) {
            ZStack {
                Circle().stroke(accent.opacity(0.2), lineWidth: 7)
                Circle().trim(from: 0, to: max(0.001, fraction))
                    .stroke(accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Image(systemName: vm.activity.type.icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(accent)
            }
            .frame(width: 64, height: 64)

            VStack(alignment: .leading, spacing: 2) {
                Text("\(grouped(current)) / \(grouped(target))\(unitSuffix)")
                    .font(.manrope(.extraBold, size: 22))
                    .foregroundColor(.primary)
                Text(liveToday != nil ? String(localized: "по данным приложений") : String(localized: "выполнено сегодня"))
                    .font(.manrope(.medium, size: 12))
                    .foregroundColor(.primary.opacity(0.45))
            }
            Spacer()
        }
        .padding(.horizontal, 34)
    }

    private func refreshLiveValue() async {
        guard isGoal else { return }
        if let v = await ConnectorService.shared.todayValue(for: vm.activity) {
            liveToday = v
            // Connector hit the target -> complete the goal automatically.
            await vm.autoCompleteIfGoalMet(connectorValue: v)
        }
    }

    private var counterControl: some View {
        HStack(spacing: 10) {
            TextField("0", text: $counterValue)
                .keyboardType(.decimalPad)
                .font(.manrope(.bold, size: 18))
                .multilineTextAlignment(.center)
                .frame(width: 92, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color.primary.opacity(0.08))
                )

            Text(vm.activity.effectiveCompletionUnit)
                .font(.manrope(.semiBold, size: 15))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 4)

            Button {
                let normalized = counterValue.replacingOccurrences(of: ",", with: ".")
                guard let value = Double(normalized), value > 0 else { return }
                Haptics.tap()
                Task {
                    await vm.submitGoalProgress(value: value, image: nil)
                    if vm.errorMessage == nil {
                        counterValue = ""
                        Haptics.success()
                    }
                }
            } label: {
                if vm.isSubmittingReport {
                    ProgressView().tint(.white)
                        .frame(width: 92, height: 48)
                } else {
                    Label("Добавить", systemImage: "plus")
                        .font(.manrope(.bold, size: 14))
                        .frame(width: 112, height: 48)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            .disabled(counterAmount == nil || vm.isSubmittingReport)
        }
        .padding(.horizontal, 28)
    }

    private var counterAmount: Double? {
        let normalized = counterValue.replacingOccurrences(of: ",", with: ".")
        guard let value = Double(normalized), value > 0 else { return nil }
        return value
    }

    private var timerControl: some View {
        VStack(spacing: 12) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text(timerText(at: context.date))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }

            HStack(spacing: 12) {
                if timerStartedAt == nil && timerAccumulated > 0 {
                    Button("Сбросить") {
                        Haptics.tap()
                        timerAccumulated = 0
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                }

                Button {
                    Haptics.tap()
                    if let started = timerStartedAt {
                        timerAccumulated += Date().timeIntervalSince(started)
                        timerStartedAt = nil
                    } else {
                        timerStartedAt = Date()
                    }
                } label: {
                    Label(
                        timerStartedAt == nil ? "Старт" : "Пауза",
                        systemImage: timerStartedAt == nil ? "play.fill" : "pause.fill"
                    )
                    .font(.manrope(.bold, size: 15))
                    .frame(minWidth: 92)
                }
                .buttonStyle(.borderedProminent)
                .tint(timerStartedAt == nil ? accent : .orange)

                if timerAccumulated > 0 && timerStartedAt == nil {
                    Button {
                        let minutes = timerAccumulated / 60
                        guard minutes > 0 else { return }
                        Haptics.tap()
                        Task {
                            await vm.submitGoalProgress(value: minutes, image: nil)
                            if vm.errorMessage == nil {
                                timerAccumulated = 0
                                Haptics.success()
                            }
                        }
                    } label: {
                        if vm.isSubmittingReport {
                            ProgressView()
                        } else {
                            Label("Зачесть", systemImage: "checkmark")
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(accent)
                    .disabled(vm.isSubmittingReport)
                }
            }
        }
    }

    private func timerText(at date: Date) -> String {
        let running = timerStartedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0
        let total = Int(timerAccumulated + running)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// Photo is required only for photo-verified task types (challenge /
    /// assignment) AND when the global setting is on. Goals/tasks/habits never
    /// need a photo, so the banner and camera step don't apply to them.
    private var needsPhoto: Bool {
        requirePhoto && vm.activity.type.requiresPhoto
    }

    // Photo requirement shown each time you open the task.
    private var photoRequirementBanner: some View {
        let line: String = {
            if let c = vm.activity.condition, !c.trimmingCharacters(in: .whitespaces).isEmpty { return c }
            return String(localized: "Сделай фото при отметке выполнения")
        }()
        return HStack(spacing: 12) {
            Image(systemName: "camera.viewfinder")
                .font(.system(size: 22))
                .foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 2) {
                Text("Нужно фото-подтверждение")
                    .font(.manrope(.bold, size: 14))
                    .foregroundColor(.primary)
                Text(line)
                    .font(.manrope(.medium, size: 13))
                    .foregroundColor(.primary.opacity(0.5))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(accent.opacity(0.12)))
    }

    private var markDoneControl: some View {
        let isAbstinence = vm.activity.effectiveCompletionMode == .abstinence
        return VStack(spacing: 10) {
            Button {
                Haptics.tap()
                if !vm.isDoneToday && needsPhoto {
                    showCamera = true
                } else {
                    Task {
                        let wasDone = vm.isDoneToday
                        await vm.toggleToday()
                        if !wasDone && vm.isDoneToday {
                            Haptics.success()
                            withAnimation { showPerfect = true }
                        }
                    }
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(vm.isDoneToday ? Color(hex: "2FB873") : Color.clear)
                        .frame(width: 72, height: 72)
                        .overlay(
                            Circle().strokeBorder(
                                vm.isDoneToday ? Color.clear : Color.primary.opacity(0.25),
                                style: StrokeStyle(lineWidth: 2, dash: vm.isDoneToday ? [] : [6])
                            )
                        )
                    Image(systemName: isAbstinence ? "hand.raised.fill" : "checkmark")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(vm.isDoneToday ? .white : .primary.opacity(0.3))
                }
            }
            Text(markDoneLabel(isAbstinence: isAbstinence))
                .font(.manrope(.medium, size: 12))
                .foregroundColor(.primary.opacity(0.4))
        }
    }

    private func markDoneLabel(isAbstinence: Bool) -> String {
        if vm.isDoneToday { return String(localized: "Нажми, чтобы отменить") }
        return isAbstinence
            ? String(localized: "Сегодня удержался")
            : String(localized: "Отметить выполненным")
    }
}

// MARK: - Connector chip

private struct ConnectorChip: View {
    let connector: DataConnector
    private let service = ConnectorService.shared
    @State private var busy = false
    private let green = Color(hex: "2FB873")

    var body: some View {
        let connected = service.isConnected(connector)
        Button {
            guard !busy else { return }
            Haptics.tap()
            busy = true
            Task {
                if connected {
                    await service.disconnect(connector)
                } else {
                    try? await service.connect(connector)
                }
                busy = false
            }
        } label: {
            VStack(spacing: 9) {
                ZStack(alignment: .topTrailing) {
                    ConnectorGlyph(connector: connector, size: 64, cornerRadius: 20,
                                   fallbackFillOpacity: connected ? 0.28 : 0.16)
                        .overlay(
                            Group {
                                if busy {
                                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                                        .fill(.ultraThinMaterial)
                                        .overlay(ProgressView().tint(connector.tint))
                                }
                            }
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(connected ? green : Color.clear, lineWidth: 2)
                        )
                    if connected {
                        Circle()
                            .fill(green)
                            .frame(width: 22, height: 22)
                            .overlay(
                                Image(systemName: "checkmark")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                            )
                            .offset(x: 6, y: -6)
                    }
                }

                Text(connector.displayName)
                    .font(.manrope(.semiBold, size: 12))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(connected ? String(localized: "Подключено") : String(localized: "Подключить"))
                    .font(.manrope(.medium, size: 10))
                    .foregroundColor(connected ? green : .primary.opacity(0.4))
            }
            .frame(width: 84)
        }
        .buttonStyle(.plain)
        .disabled(busy)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: connected)
    }
}

// MARK: - Number formatting

private let groupedFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.groupingSeparator = " "
    // 1 digit so converted distances (3.1 миль) don't round to whole numbers.
    f.maximumFractionDigits = 1
    return f
}()

private func grouped(_ value: Double) -> String {
    groupedFormatter.string(from: NSNumber(value: value)) ?? "\(Int(value))"
}

// MARK: - Day cell

private struct DayCellModel {
    let date: Date?
    let day: Int?
}

private struct DayCell: View {
    let cell: DayCellModel
    let done: Bool
    let isToday: Bool
    let orange: Color
    let blue: Color

    var body: some View {
        ZStack {
            if cell.day == nil {
                Color.clear.frame(height: 40)
            } else {
                Circle()
                    .fill(done ? orange : Color.primary.opacity(0.06))
                    .frame(width: 40, height: 40)
                    .overlay {
                        if isToday {
                            Circle().strokeBorder(blue, style: StrokeStyle(lineWidth: 2, dash: done ? [] : [4]))
                        }
                    }
                if done {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 16))
                        .foregroundColor(.white)
                } else {
                    Text("\(cell.day ?? 0)")
                        .font(.manrope(.medium, size: 15))
                        .foregroundColor(.primary.opacity(0.55))
                }
            }
        }
        .frame(height: 40)
    }
}
