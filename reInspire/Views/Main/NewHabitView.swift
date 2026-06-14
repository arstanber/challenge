import SwiftUI

// MARK: - Draft passed into the editor (prefilled for presets, empty for custom)

struct HabitDraft: Identifiable {
    let id = UUID()
    var title: String = ""
    var icon: String = "star.fill"
    var tint: Color = Color(hex: "F5A623")
    var goalEnabled: Bool = false
    var goalTarget: Double? = nil
    var condition: String = ""
}

// MARK: - New habit editor

struct NewHabitView: View {
    let vm: ActivitiesViewModel
    var onCreated: () -> Void = {}

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var icon: String
    @State private var tint: Color
    @State private var polarity = "Развить"          // Развить / Бросить
    @State private var repeatMode = "Ежедневно"      // Ежедневно / Еженедельно
    @State private var selectedDays: Set<Int> = Set(0..<7)
    @State private var goalOn: Bool
    @State private var goalValue: String
    @State private var goalUnit: String
    @State private var reminderOn = false
    @State private var reminderTime = NewHabitView.defaultReminder()
    @State private var photoDesc: String
    @State private var showPalette = false
    @State private var creating = false
    @State private var suggestingCondition = false

    init(draft: HabitDraft, vm: ActivitiesViewModel, onCreated: @escaping () -> Void = {}) {
        self.vm = vm
        self.onCreated = onCreated
        _title = State(initialValue: draft.title)
        _icon = State(initialValue: draft.icon)
        _tint = State(initialValue: draft.tint)
        _goalOn = State(initialValue: draft.goalEnabled)
        _goalValue = State(initialValue: draft.goalTarget.map { String(Int($0)) } ?? "")
        _goalUnit = State(initialValue: "")
        _photoDesc = State(initialValue: draft.condition)
    }

    private static func defaultReminder() -> Date {
        Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
    }

    private let icons = ["sunrise.fill", "figure.walk", "figure.run", "book.fill", "drop.fill",
                         "figure.mind.and.body", "dumbbell.fill", "bed.double.fill", "fork.knife",
                         "graduationcap.fill", "pencil.and.outline", "heart.fill", "leaf.fill",
                         "cup.and.saucer.fill", "moon.zzz.fill", "star.fill"]
    private let palette = ["F5A623", "FF4D4D", "2FB873", "3D9BFF", "A86CFF",
                           "18C29C", "FF7AB6", "FFD93D", "FF8A3D", "5B7CFF"]
    private let weekdays = ["П", "В", "С", "Ч", "П", "С", "В"]

    private var canCreate: Bool { !title.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        ZStack(alignment: .bottom) {
            background

            ScrollView(showsIndicators: false) {
                VStack(spacing: 16) {
                    nameRow
                    if showPalette { paletteRow }
                    typeRow
                    repeatRow
                    goalRow
                    photoRow
                    reminderRow
                    Color.clear.frame(height: 110)
                }
                .padding(.horizontal, 18)
                .padding(.top, 70)
                .readableWidth()
            }

            createButton
        }
        .overlay(alignment: .top) { header }
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: showPalette)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: goalOn)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: reminderOn)
        .animation(.easeInOut(duration: 0.25), value: tint)
    }

    // MARK: Background

    private var background: some View {
        ZStack {
            Color(.systemBackground)
            LinearGradient(
                stops: [
                    .init(color: tint.opacity(0.38), location: 0.0),
                    .init(color: tint.opacity(0.10), location: 0.22),
                    .init(color: .clear, location: 0.5)
                ],
                startPoint: .top, endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Text("Новая привычка")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.primary)
            HStack {
                Spacer()
                Button { Haptics.tap(); dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white.opacity(0.85))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.red.opacity(0.35)))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
    }

    // MARK: Name row

    private var nameRow: some View {
        HStack(spacing: 12) {
            Menu {
                ForEach(icons, id: \.self) { ic in
                    Button { Haptics.selection(); icon = ic } label: { Label(ic, systemImage: ic) }
                }
            } label: {
                Circle()
                    .fill(tint.opacity(0.2))
                    .frame(width: 58, height: 58)
                    .overlay(Image(systemName: icon).font(.system(size: 24)).foregroundStyle(tint))
            }

            TextField("", text: $title, prompt: Text("Название").foregroundColor(.secondary))
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(.primary)
                .padding(.horizontal, 18)
                .frame(height: 58)
                .frame(maxWidth: .infinity)
                .background { field }

            Button { Haptics.selection(); showPalette.toggle() } label: {
                Circle().fill(tint).frame(width: 58, height: 58)
            }
        }
    }

    private var paletteRow: some View {
        HStack(spacing: 12) {
            ForEach(palette, id: \.self) { hex in
                let color = Color(hex: hex)
                Button { Haptics.selection(); tint = color; showPalette = false } label: {
                    Circle()
                        .fill(color)
                        .frame(width: 34, height: 34)
                        .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: tint == color ? 3 : 0))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: Type

    private var typeRow: some View {
        HStack {
            Text("Тип").font(.system(size: 19, weight: .medium)).foregroundStyle(.primary)
            Spacer()
            Menu {
                Button("Развить") { polarity = "Развить" }
                Button("Бросить") { polarity = "Бросить" }
            } label: { valueLabel(polarity) }
        }
        .padding(18)
        .background { field }
    }

    // MARK: Repeat

    private var repeatRow: some View {
        VStack(spacing: 14) {
            HStack {
                Text("Повтор").font(.system(size: 19, weight: .medium)).foregroundStyle(.primary)
                Spacer()
                Menu {
                    Button("Ежедневно") { repeatMode = "Ежедневно"; selectedDays = Set(0..<7) }
                    Button("Еженедельно") { repeatMode = "Еженедельно" }
                } label: { valueLabel(repeatMode) }
            }
            Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
            HStack(spacing: 8) {
                // Ordered by the week-start setting; storage stays 0=Mon..6=Sun.
                ForEach(AppPrefs.orderedIsoWeekdays, id: \.self) { iso in
                    let i = iso - 1
                    let on = selectedDays.contains(i)
                    Button {
                        Haptics.selection()
                        if on { selectedDays.remove(i) } else { selectedDays.insert(i) }
                        repeatMode = selectedDays.count == 7 ? "Ежедневно" : "Еженедельно"
                    } label: {
                        Text(weekdays[i])
                            .font(.system(size: 17, weight: .bold))
                            .foregroundColor(on ? .black : .primary.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .background(Circle().fill(on ? tint : tint.opacity(0.15)))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(18)
        .background { field }
    }

    // MARK: Goal

    private var goalRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 14) {
                HStack {
                    Text("Цель").font(.system(size: 19, weight: .medium)).foregroundStyle(.primary)
                    Spacer()
                    Toggle("", isOn: $goalOn).labelsHidden().tint(tint)
                }
                if goalOn {
                    Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
                    HStack(spacing: 10) {
                        TextField("", text: $goalValue, prompt: Text("10 000").foregroundColor(.secondary))
                            .keyboardType(.numberPad)
                            .font(.system(size: 18, weight: .semibold))
                            .frame(width: 110)
                            .padding(.vertical, 10).padding(.horizontal, 14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.08)))
                        TextField("", text: $goalUnit, prompt: Text("шагов / мин / км").foregroundColor(.secondary))
                            .font(.system(size: 18))
                            .padding(.vertical, 10).padding(.horizontal, 14)
                            .background(RoundedRectangle(cornerRadius: 12).fill(Color.primary.opacity(0.08)))
                    }
                }
            }
            .padding(18)
            .background { field }

            Text("Добавьте цель, например \"10 страниц\", \"30 мин\" или \"5 км\".")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 10)
        }
    }

    // MARK: Photo proof

    private var photoRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 14) {
                HStack(spacing: 10) {
                    Image(systemName: "camera.fill").font(.system(size: 18)).foregroundStyle(tint)
                    Text("Фото-подтверждение").font(.system(size: 19, weight: .medium)).foregroundStyle(.primary)
                    Spacer()
                    Button {
                        Task { await suggestCondition() }
                    } label: {
                        HStack(spacing: 5) {
                            if suggestingCondition {
                                ProgressView().controlSize(.small).tint(tint)
                            } else {
                                Image(systemName: "sparkles").font(.system(size: 13, weight: .bold))
                            }
                            Text("Подобрать").font(.manrope(.semiBold, size: 13))
                        }
                        .foregroundStyle(tint)
                        .padding(.horizontal, 12).padding(.vertical, 7)
                        .background(Capsule().fill(tint.opacity(0.12)))
                    }
                    .buttonStyle(.plain)
                    .disabled(suggestingCondition || title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
                TextField("", text: $photoDesc,
                          prompt: Text("Например: фото открытой книги").foregroundColor(.secondary),
                          axis: .vertical)
                    .font(.system(size: 17))
                    .foregroundStyle(.primary)
                    .lineLimit(1...3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(18)
            .background { field }

            Text("Какое фото нужно сделать, чтобы засчитать выполнение. Фото требуется всегда, если в настройках не выключено.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 8)
                .padding(.top, 10)
        }
    }

    // MARK: Reminder

    private var reminderRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: 14) {
                HStack {
                    Text("Напоминание").font(.system(size: 19, weight: .medium)).foregroundStyle(.primary)
                    Spacer()
                    Toggle("", isOn: $reminderOn).labelsHidden().tint(tint)
                }
                if reminderOn {
                    Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1)
                    DatePicker("", selection: $reminderTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(18)
            .background { field }

            Text("Мы напомним только, если привычка ещё не выполнена.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 10)
        }
    }

    // MARK: Create

    private var createButton: some View {
        Button { create() } label: {
            Text("Создать")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(Capsule().fill(canCreate ? tint : tint.opacity(0.4)))
        }
        .buttonStyle(.haptic)
        .disabled(!canCreate || creating)
        .padding(.horizontal, 18)
        .padding(.bottom, 30)
        .readableWidth(480)
    }

    // MARK: Helpers

    private var field: some View {
        RoundedRectangle(cornerRadius: 22, style: .continuous).fill(tint.opacity(0.12))
    }

    private func valueLabel(_ text: String) -> some View {
        HStack(spacing: 6) {
            Text(text).font(.system(size: 18)).foregroundStyle(.secondary)
            Image(systemName: "chevron.up.chevron.down")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }

    private func suggestCondition() async {
        let name = title.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, !suggestingCondition else { return }
        Haptics.tap()
        suggestingCondition = true
        defer { suggestingCondition = false }
        if let suggestion = await AIVerificationService.shared.suggestCondition(title: name) {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                photoDesc = suggestion
            }
            Haptics.success()
        } else {
            Haptics.warning()
        }
    }

    private func create() {
        guard canCreate, !creating else { return }
        creating = true
        Haptics.success()
        let freq: ActivityFrequency = repeatMode == "Ежедневно" ? .daily : .weekly
        let goal: Double? = goalOn ? Double(goalValue.filter(\.isNumber)) : nil
        let type: ActivityType = goalOn ? .goal : .habit
        let condition = photoDesc.trimmingCharacters(in: .whitespacesAndNewlines)
        // Picker indices are 0-based Monday-first; schedule_days is ISO 1=Mon..7=Sun.
        let days: [Int]? = freq == .weekly && selectedDays.count < 7 && !selectedDays.isEmpty
            ? selectedDays.sorted().map { $0 + 1 }
            : nil
        Task {
            await vm.createActivity(
                title: title.trimmingCharacters(in: .whitespaces),
                type: type,
                frequency: freq,
                goalTarget: goal,
                reminderTime: reminderOn ? reminderTime : nil,
                condition: condition.isEmpty ? nil : condition,
                scheduleDays: days
            )
            onCreated()
            dismiss()
        }
    }
}
