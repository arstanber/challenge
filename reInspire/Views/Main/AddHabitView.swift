import SwiftUI

// MARK: - Categories

private enum HabitCategory: String, CaseIterable, Identifiable {
    case popular, health, mind, productivity
    var id: String { rawValue }

    var title: String {
        switch self {
        case .popular:      return "Популярные"
        case .health:       return "Здоровье"
        case .mind:         return "Развитие"
        case .productivity: return "Продуктивность"
        }
    }

    var icon: String {
        switch self {
        case .popular:      return "flame.fill"
        case .health:       return "heart.fill"
        case .mind:         return "brain.head.profile"
        case .productivity: return "bolt.fill"
        }
    }
}

// MARK: - Template model + catalog

private struct HabitTemplate: Identifiable {
    let id = UUID()
    let title: String
    let icon: String
    let tint: Color
    let subtitle: String?
    let type: ActivityType
    let goalTarget: Double?
    let healthLinked: Bool
    let categories: Set<HabitCategory>
    /// Data connector this habit pairs with -- shown as a badge; the
    /// suggestion engine offers to connect it right after creation.
    var connector: DataConnector? = nil

    static func tint(_ hex: String) -> Color { Color(hex: hex) }

    static let all: [HabitTemplate] = [
        .init(title: "Просыпаться рано", icon: "sunrise.fill", tint: tint("FF8A3D"), subtitle: nil,
              type: .habit, goalTarget: nil, healthLinked: false, categories: [.popular]),
        .init(title: "Ежедневные шаги", icon: "figure.walk", tint: tint("2FB873"), subtitle: "10 000 шагов",
              type: .goal, goalTarget: 10000, healthLinked: true, categories: [.popular, .health],
              connector: .appleHealth),
        .init(title: "Тренировка", icon: "figure.run", tint: tint("FF4D4D"), subtitle: "30 мин",
              type: .goal, goalTarget: 30, healthLinked: true, categories: [.popular, .health],
              connector: .appleFitness),
        .init(title: "Вставать по будильнику", icon: "alarm.fill", tint: tint("FF9F0A"), subtitle: "07:00",
              type: .habit, goalTarget: nil, healthLinked: false, categories: [.popular, .productivity],
              connector: .appleClock),
        .init(title: "Утренняя пробежка", icon: "figure.outdoor.cycle", tint: tint("FC4C02"), subtitle: "3 км",
              type: .goal, goalTarget: 3, healthLinked: true, categories: [.popular, .health],
              connector: .strava),
        .init(title: "День по календарю", icon: "calendar", tint: tint("4285F4"), subtitle: "Без пропущенных встреч",
              type: .habit, goalTarget: nil, healthLinked: false, categories: [.popular, .productivity],
              connector: .appleCalendar),
        .init(title: "Фото-отчёт в Telegram", icon: "paperplane.fill", tint: tint("29A9EA"), subtitle: nil,
              type: .habit, goalTarget: nil, healthLinked: false, categories: [.popular],
              connector: .telegram),
        .init(title: "Здоровый сон", icon: "moon.zzz.fill", tint: tint("A86CFF"), subtitle: "8 часов",
              type: .habit, goalTarget: nil, healthLinked: true, categories: [.popular, .health],
              connector: .appleHealth),
        .init(title: "Читать", icon: "book.fill", tint: tint("3D9BFF"), subtitle: "30 мин",
              type: .habit, goalTarget: nil, healthLinked: false, categories: [.popular, .mind]),
        .init(title: "Медитировать", icon: "figure.mind.and.body", tint: tint("A86CFF"), subtitle: "10 мин",
              type: .habit, goalTarget: nil, healthLinked: false, categories: [.popular, .mind, .health]),
        .init(title: "Пить воду", icon: "drop.fill", tint: tint("28C2D6"), subtitle: "2 л",
              type: .habit, goalTarget: nil, healthLinked: false, categories: [.popular, .health]),
        .init(title: "Планировать день", icon: "checklist", tint: tint("5B7CFF"), subtitle: nil,
              type: .habit, goalTarget: nil, healthLinked: false, categories: [.popular, .productivity]),
        .init(title: "Вести дневник", icon: "pencil.and.outline", tint: tint("FFB23D"), subtitle: nil,
              type: .habit, goalTarget: nil, healthLinked: false, categories: [.popular, .mind]),
        .init(title: "Зарядка", icon: "dumbbell.fill", tint: tint("FF4D4D"), subtitle: "10 мин",
              type: .goal, goalTarget: 10, healthLinked: true, categories: [.health]),
        .init(title: "Растяжка", icon: "figure.flexibility", tint: tint("18C29C"), subtitle: "10 мин",
              type: .habit, goalTarget: nil, healthLinked: false, categories: [.health]),
        .init(title: "Холодный душ", icon: "snowflake", tint: tint("28C2D6"), subtitle: nil,
              type: .habit, goalTarget: nil, healthLinked: false, categories: [.health]),
        .init(title: "Ранний отбой", icon: "bed.double.fill", tint: tint("A86CFF"), subtitle: "23:00",
              type: .habit, goalTarget: nil, healthLinked: false, categories: [.health, .productivity]),
        .init(title: "Без сахара", icon: "fork.knife", tint: tint("FF7A3D"), subtitle: nil,
              type: .habit, goalTarget: nil, healthLinked: false, categories: [.health]),
        .init(title: "Учить язык", icon: "character.bubble.fill", tint: tint("5B7CFF"), subtitle: "15 мин",
              type: .habit, goalTarget: nil, healthLinked: false, categories: [.mind]),
        .init(title: "Учиться", icon: "graduationcap.fill", tint: tint("3D9BFF"), subtitle: "1 час",
              type: .habit, goalTarget: nil, healthLinked: false, categories: [.mind, .productivity]),
        .init(title: "Без телефона перед сном", icon: "moon.zzz.fill", tint: tint("8A7CFF"), subtitle: nil,
              type: .habit, goalTarget: nil, healthLinked: false, categories: [.mind, .productivity]),
        .init(title: "Убраться дома", icon: "house.fill", tint: tint("18C29C"), subtitle: nil,
              type: .habit, goalTarget: nil, healthLinked: false, categories: [.productivity])
    ]

    static func count(_ category: HabitCategory) -> Int {
        all.filter { $0.categories.contains(category) }.count
    }
}

// MARK: - Add Habit screen

struct AddHabitView: View {
    /// Called when a preset is tapped — host opens the New-habit editor prefilled with this draft.
    let onPick: (HabitDraft) -> Void
    /// Creation-method popup choices ("Своя привычка" opens the popup right
    /// on this page); the host presents the matching flow after dismissal.
    let onAIStepByStep: () -> Void
    let onBySaying: () -> Void
    let onByYourself: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var category: HabitCategory = .popular
    @State private var showCreateMenu = false

    private var templates: [HabitTemplate] {
        HabitTemplate.all.filter { $0.categories.contains(category) }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            Color(.systemBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                header
                categoryBar
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(category.title)
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(.primary)
                            .padding(.top, 6)

                        if let featured = templates.first {
                            FeaturedCard(template: featured) { pick(featured) }
                        }
                        ForEach(templates.dropFirst()) { t in
                            TemplateRow(template: t) { pick(t) }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 130)
                    .readableWidth()
                }
            }

            customButton

            if showCreateMenu {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .hapticTap {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showCreateMenu = false }
                    }
                VStack {
                    Spacer()
                    CreationMenuPopup(
                        onAIStepByStep: { choose(onAIStepByStep) },
                        onBySaying: { choose(onBySaying) },
                        onByYourself: { choose(onByYourself) }
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 40)
                    .readableWidth(480)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Text("Добавить новую привычку")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)

            HStack {
                Spacer()
                Button { Haptics.tap(); dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.primary.opacity(0.7))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color.primary.opacity(0.1)))
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    // MARK: Category chips

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(HabitCategory.allCases) { c in
                    let selected = c == category
                    Button {
                        Haptics.selection()
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { category = c }
                    } label: {
                        HStack(spacing: 7) {
                            Image(systemName: c.icon).font(.system(size: 13, weight: .semibold))
                            Text(c.title).font(.system(size: 15, weight: .semibold))
                            Text("• \(HabitTemplate.count(c))")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .foregroundStyle(selected ? .primary : Color.primary.opacity(0.55))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 11)
                        .background(
                            Capsule().fill(Color.primary.opacity(selected ? 0.12 : 0.05))
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 8)
    }

    // MARK: Custom-habit button

    private var customButton: some View {
        Button {
            Haptics.tap()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) { showCreateMenu = true }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.system(size: 18, weight: .bold))
                Text("Своя привычка").font(.system(size: 19, weight: .semibold))
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 62)
            .background(Capsule().fill(Color(hex: "0A84FF")))
            .padding(.horizontal, 40)
        }
        .buttonStyle(.haptic)
        .padding(.bottom, 30)
        .readableWidth(480)
    }

    // MARK: Actions

    /// A creation method was chosen from the popup: close everything and let
    /// the host present the flow once the sheet's dismissal settles.
    private func choose(_ action: @escaping () -> Void) {
        showCreateMenu = false
        dismiss()
        action()
    }

    private func pick(_ template: HabitTemplate) {
        Haptics.selection()
        onPick(HabitDraft(
            title: template.title,
            icon: template.icon,
            tint: template.tint,
            goalEnabled: template.goalTarget != nil,
            goalTarget: template.goalTarget
        ))
    }
}

// MARK: - Featured card

private struct FeaturedCard: View {
    let template: HabitTemplate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [template.tint.opacity(0.55), template.tint, template.tint.opacity(0.85)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
                .overlay(
                    Image(systemName: template.icon)
                        .font(.system(size: 120, weight: .regular))
                        .foregroundStyle(.white.opacity(0.18))
                        .offset(x: 90, y: -30)
                )

                HStack(alignment: .bottom) {
                    HStack(spacing: 10) {
                        Image(systemName: template.icon)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.white)
                        Text(template.title)
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    frequencyTag(light: true)
                }
                .padding(18)
            }
            .frame(height: 190)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Template row

private struct TemplateRow: View {
    let template: HabitTemplate
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: template.icon)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(template.tint)
                    .frame(width: 30)

                VStack(alignment: .leading, spacing: 3) {
                    Text(template.title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let sub = template.subtitle {
                        HStack(spacing: 5) {
                            Text(sub)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(.secondary)
                            if template.healthLinked && template.connector == nil {
                                Image(systemName: "heart.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    if let connector = template.connector {
                        HStack(spacing: 5) {
                            ConnectorGlyph(connector: connector, size: 14, cornerRadius: 4)
                            Text(connector.displayName)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(connector.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(connector.tint.opacity(0.12)))
                    }
                }

                Spacer(minLength: 8)

                frequencyTag(light: false)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [template.tint.opacity(0.16), template.tint.opacity(0.05)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        )
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Shared frequency tag

private func frequencyTag(light: Bool) -> some View {
    HStack(spacing: 6) {
        Image(systemName: "arrow.triangle.2.circlepath")
            .font(.system(size: 13, weight: .semibold))
        Text("Каждый день")
            .font(.system(size: 15, weight: .medium))
    }
    .foregroundStyle(light ? Color.white.opacity(0.95) : Color.secondary)
}
