import SwiftUI

// MARK: - Home view mode (the "Вид по умолчанию" setting picks the initial one)

enum HomeViewMode: String, CaseIterable, Identifiable {
    case day = "День"
    case week = "Неделя"
    case month = "Месяц"
    var id: String { rawValue }
}

// MARK: - Mode switcher

struct HomeModeSwitcher: View {
    @Binding var mode: HomeViewMode

    var body: some View {
        HStack(spacing: 4) {
            ForEach(HomeViewMode.allCases) { m in
                Button {
                    Haptics.selection()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { mode = m }
                } label: {
                    Text(m.rawValue)
                        .font(.manrope(mode == m ? .bold : .medium, size: 14))
                        .foregroundColor(mode == m ? .primary : .primary.opacity(0.45))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background {
                            if mode == m {
                                Capsule()
                                    .fill(Color(.systemBackground))
                                    .shadow(color: .black.opacity(0.08), radius: 4, y: 1)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}

// MARK: - Shared scheduling

/// Top-level active tasks that land on `date`: recurring ones scheduled that
/// weekday (until their expiry), one-time ones with a deadline that day.
func plannerTasks(on date: Date, from activities: [Activity], calendar: Calendar) -> [Activity] {
    let dayStart = calendar.startOfDay(for: date)
    guard let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) else { return [] }
    return activities.filter { a in
        guard a.parentId == nil, a.status == .active else { return false }
        if a.frequency == .once {
            guard let d = a.deadline else { return calendar.isDateInToday(date) }
            return d >= dayStart && d < dayEnd
        }
        guard a.isScheduled(on: date) else { return false }
        if let d = a.deadline, d < dayStart { return false }
        return true
    }
}

// MARK: - Compact task row (week/month planner)

struct PlannerTaskRow: View {
    let task: Activity
    var done = false
    let onTap: () -> Void

    private var accent: Color {
        switch task.type {
        case .challenge:  return Color(hex: "0048E2")
        case .goal:       return Color(hex: "2FB873")
        case .task:       return Color(hex: "FF7A00")
        case .habit:      return Color(hex: "8B5CF6")
        case .assignment: return Color(hex: "EC4899")
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Circle()
                    .fill(accent.opacity(0.15))
                    .frame(width: 36, height: 36)
                    .overlay {
                        Image(systemName: task.type.icon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(accent)
                    }

                Text(task.title)
                    .font(.manrope(.semiBold, size: 15))
                    .foregroundColor(done ? .primary.opacity(0.35) : .primary)
                    .strikethrough(done, color: .primary.opacity(0.35))
                    .lineLimit(1)

                Spacer(minLength: 8)

                if let t = task.reminderTime {
                    // Respects the 12/24h locale override from RootView.
                    Text(t, style: .time)
                        .font(.manrope(.medium, size: 13))
                        .foregroundColor(.primary.opacity(0.4))
                }
                if done {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color(hex: "30D158"))
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.primary.opacity(0.04))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Week agenda

struct WeekAgendaView: View {
    let activities: [Activity]
    let isHandledToday: (UUID) -> Bool
    let onOpen: (Activity) -> Void

    private let cal = AppPrefs.calendar

    private var weekDays: [Date] {
        let today = cal.startOfDay(for: Date())
        guard let interval = cal.dateInterval(of: .weekOfYear, for: today) else { return [] }
        return (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: interval.start) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            ForEach(weekDays, id: \.self) { day in
                daySection(day)
            }
        }
    }

    @ViewBuilder
    private func daySection(_ day: Date) -> some View {
        let tasks = plannerTasks(on: day, from: activities, calendar: cal)
        let isToday = cal.isDateInToday(day)
        VStack(alignment: .leading, spacing: 8) {
            Text(isToday ? "Сегодня" : dayTitle(day))
                .font(.manrope(.bold, size: 15))
                .foregroundColor(isToday ? .primary : .primary.opacity(0.45))
                .padding(.leading, 4)

            if tasks.isEmpty {
                Text("Нет задач")
                    .font(.manrope(.medium, size: 13))
                    .foregroundColor(.primary.opacity(0.25))
                    .padding(.leading, 4)
            } else {
                ForEach(tasks) { task in
                    PlannerTaskRow(
                        task: task,
                        done: isToday && isHandledToday(task.id),
                        onTap: { onOpen(task) }
                    )
                }
            }
        }
    }

    private func dayTitle(_ day: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EEEE, d MMMM"
        return f.string(from: day).capitalized
    }
}

// MARK: - Month planner

struct MonthPlannerView: View {
    let activities: [Activity]
    let isHandledToday: (UUID) -> Bool
    let onOpen: (Activity) -> Void

    @State private var monthOffset = 0
    @State private var selected = AppPrefs.calendar.startOfDay(for: Date())
    private let cal = AppPrefs.calendar

    private var monthDate: Date {
        cal.date(byAdding: .month, value: monthOffset, to: Date()) ?? Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            weekdayHeaders
            grid
            selectedDayList
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            Image(systemName: "calendar").foregroundColor(.primary.opacity(0.5))
            Text(monthTitle)
                .font(.manrope(.bold, size: 20))
                .foregroundColor(.primary)
            Spacer()
            Button { Haptics.selection(); withAnimation { monthOffset -= 1 } } label: {
                Image(systemName: "chevron.left")
                    .foregroundColor(.primary.opacity(0.4))
                    .frame(width: 32, height: 32)
            }
            Button { Haptics.selection(); withAnimation { monthOffset += 1 } } label: {
                Image(systemName: "chevron.right")
                    .foregroundColor(.primary.opacity(0.4))
                    .frame(width: 32, height: 32)
            }
        }
    }

    private var monthTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "LLLL yyyy"
        return f.string(from: monthDate).capitalized
    }

    // MARK: Grid

    private var weekdayHeaders: some View {
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
    }

    private var monthDays: [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: monthDate) else { return [] }
        let firstDay = interval.start
        let weekday = cal.component(.weekday, from: firstDay)
        let leading = (weekday - cal.firstWeekday + 7) % 7
        let count = cal.range(of: .day, in: .month, for: monthDate)?.count ?? 30
        return Array(repeating: nil, count: leading)
            + (0..<count).map { cal.date(byAdding: .day, value: $0, to: firstDay) }
    }

    private var grid: some View {
        let cols = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        return LazyVGrid(columns: cols, spacing: 8) {
            ForEach(Array(monthDays.enumerated()), id: \.offset) { _, date in
                if let date {
                    dayCell(date)
                } else {
                    Color.clear.frame(height: 44)
                }
            }
        }
    }

    private func dayCell(_ date: Date) -> some View {
        let count = plannerTasks(on: date, from: activities, calendar: cal).count
        let isToday = cal.isDateInToday(date)
        let isSelected = cal.isDate(date, inSameDayAs: selected)
        return Button {
            Haptics.selection()
            withAnimation(.spring(response: 0.25, dampingFraction: 0.85)) { selected = date }
        } label: {
            VStack(spacing: 4) {
                Text("\(cal.component(.day, from: date))")
                    .font(.manrope(isToday ? .extraBold : .medium, size: 15))
                    .foregroundColor(isToday ? Color(hex: "4580FF") : .primary.opacity(0.75))
                HStack(spacing: 3) {
                    ForEach(0..<min(count, 3), id: \.self) { _ in
                        Circle().fill(Color(hex: "4580FF").opacity(0.6)).frame(width: 4, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(isSelected ? Color(hex: "4580FF").opacity(0.12) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(isSelected ? Color(hex: "4580FF").opacity(0.5) : .clear, lineWidth: 1.5)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Selected day

    @ViewBuilder
    private var selectedDayList: some View {
        let tasks = plannerTasks(on: selected, from: activities, calendar: cal)
        let isToday = cal.isDateInToday(selected)
        VStack(alignment: .leading, spacing: 8) {
            Text(isToday ? "Сегодня" : selectedTitle)
                .font(.manrope(.bold, size: 15))
                .foregroundColor(.primary.opacity(0.6))
                .padding(.top, 8)
                .padding(.leading, 4)

            if tasks.isEmpty {
                Text("Нет задач в этот день")
                    .font(.manrope(.medium, size: 13))
                    .foregroundColor(.primary.opacity(0.25))
                    .padding(.leading, 4)
            } else {
                ForEach(tasks) { task in
                    PlannerTaskRow(
                        task: task,
                        done: isToday && isHandledToday(task.id),
                        onTap: { onOpen(task) }
                    )
                }
            }
        }
    }

    private var selectedTitle: String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.dateFormat = "EEEE, d MMMM"
        return f.string(from: selected).capitalized
    }
}
