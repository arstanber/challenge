import SwiftUI

/// Detail sheet opened by tapping the "Сегодня, <date>" header on Home.
/// Shows the user's current streak, best streak and the streak-freeze wallet,
/// plus a one-tap action to freeze yesterday when the run is at risk.
struct StreakDetailView: View {
    let vm: ActivitiesViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var isFreezing = false
    @State private var shareRequest: ShareRequest?

    private var streak: Int { vm.globalStreakCurrent }
    private var best: Int { vm.globalStreakBest }
    private var freezes: Int { vm.freezesAvailable }
    private var canFreezeYesterday: Bool {
        vm.yesterdayFreezable && vm.freezesAvailable > 0
    }

    private static let frozenBlue = Color(red: 0.0, green: 0.478, blue: 1.0)

    /// Today's goal met -> orange; otherwise a freeze on yesterday is holding
    /// the run -> blue; nothing keeping it lit today -> gray.
    private var flameColor: Color {
        if vm.todayGoalMet { return .orange }
        if vm.yesterdayFrozen { return Self.frozenBlue }
        return .secondary
    }

    /// Use the filled flame whenever it is lit (orange or blue); a cold gray
    /// day shows the hollow outline.
    private var flameLit: Bool { vm.todayGoalMet || vm.yesterdayFrozen }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    flameHeader

                    WeekStreakStrip(days: vm.last7Days)

                    HStack(spacing: 12) {
                        StatTile(emoji: "🏆",
                                 value: "\(best)",
                                 caption: "Лучшая серия")
                        StatTile(emoji: "🧊",
                                 value: "\(freezes)",
                                 caption: "Заморозки")
                    }

                    if streak > 0 {
                        shareButton
                    }

                    explainer

                    if canFreezeYesterday {
                        freezeButton
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .background(Color(.systemBackground))
            .sheet(item: $shareRequest) { req in
                ShareComposerView(kind: req.kind, name: req.name)
            }
            .navigationTitle("Твоя серия")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { dismiss() }
                        .font(.sfProDisplay(16, weight: .semibold))
                }
            }
        }
    }

    // MARK: - Flame header

    private var flameHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: flameLit ? "flame.fill" : "flame")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(flameColor)
                .symbolEffect(.bounce, value: streak)
                .animation(.easeInOut(duration: 0.25), value: flameColor)

            Text("\(streak)")
                .font(.sfProDisplay(56, weight: .bold))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())

            Text(streak == 1 ? "день подряд" : "дней подряд")
                .font(.sfProDisplay(16, weight: .semibold))
                .foregroundStyle(.secondary)

            flameStatus
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    /// One-line cue that explains the flame's color.
    @ViewBuilder
    private var flameStatus: some View {
        if vm.yesterdayFrozen && !vm.todayGoalMet {
            statusPill(text: vm.yesterdayAutoFrozen
                       ? "Заморозка использована автоматически"
                       : "Вчера спасла заморозка",
                       color: Self.frozenBlue)
        } else if !vm.todayGoalMet {
            statusPill(text: "Сегодня ещё не выполнено", color: .secondary)
        }
    }

    private func statusPill(text: String, color: Color) -> some View {
        Text(text)
            .font(.sfProDisplay(13, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(color.opacity(0.12), in: Capsule())
            .padding(.top, 4)
    }

    // MARK: - Explainer

    private var explainer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Text("🧊").font(.system(size: 22))
                VStack(alignment: .leading, spacing: 2) {
                    Text("Как работают заморозки")
                        .font(.sfProDisplay(15, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text("Если ты пропустил день, заморозка применяется автоматически -- день засчитывается, и серия не прерывается. Новые заморозки начисляются за каждые 7 дней лучшей серии.")
                        .font(.sfProDisplay(13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    // MARK: - Share

    private var shareButton: some View {
        Button {
            Haptics.tap()
            shareRequest = ShareRequest(kind: .streak(days: streak, best: best),
                                        name: AuthService.shared.currentUser?.displayLabel)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "square.and.arrow.up")
                Text("Поделиться серией")
                    .font(.sfProDisplay(16, weight: .semibold))
            }
            .foregroundStyle(Color.accentColor)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(Color.accentColor.opacity(0.5), lineWidth: 1.5))
        }
        .buttonStyle(.haptic)
    }

    // MARK: - Freeze yesterday

    private var freezeButton: some View {
        Button {
            guard !isFreezing else { return }
            isFreezing = true
            Haptics.tap()
            Task {
                await vm.freezeYesterday()
                isFreezing = false
            }
        } label: {
            HStack(spacing: 8) {
                if isFreezing {
                    ProgressView().tint(.white)
                } else {
                    Text("🧊")
                    Text("Заморозить вчерашний день")
                        .font(.sfProDisplay(16, weight: .semibold))
                }
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 54)
            .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 16))
        }
        .disabled(isFreezing)
    }
}

// MARK: - Week strip (GitHub-style trailing 7 days)

/// A row of 7 day squares -- the last week ending today -- mirroring the
/// month heatmap from the widget. Filled (orange) when the daily goal was met;
/// today gets a ring; days with no local data render faint.
private struct WeekStreakStrip: View {
    let days: [ActivitiesViewModel.WeekDayProgress]

    private static let active = Color(red: 0.980, green: 0.325, blue: 0.110)

    private static let weekdayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "ru_RU")
        f.setLocalizedDateFormatFromTemplate("EEEEEE") // short standalone weekday
        return f
    }()

    private var metCount: Int { days.filter { $0.hasData && $0.met }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("Эта неделя")
                    .font(.sfProDisplay(16, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(metCount)/7")
                    .font(.sfProDisplay(15, weight: .bold))
                    .foregroundStyle(Self.active)
                    .contentTransition(.numericText())
            }

            HStack(spacing: 8) {
                ForEach(days) { day in
                    VStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(fill(for: day))
                            .aspectRatio(1, contentMode: .fit)
                            .overlay {
                                if day.isToday {
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .strokeBorder(Self.active, lineWidth: 2)
                                }
                            }
                        Text(Self.weekdayFormatter.string(from: day.date))
                            .font(.sfProDisplay(11, weight: .medium))
                            .foregroundStyle(day.isToday ? Self.active : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }

    private func fill(for day: ActivitiesViewModel.WeekDayProgress) -> Color {
        if day.met { return Self.active }
        if !day.hasData { return Color.primary.opacity(0.04) }
        return Color.primary.opacity(0.09)
    }
}

// MARK: - Stat tile

private struct StatTile: View {
    let emoji: String
    let value: String
    let caption: String

    var body: some View {
        VStack(spacing: 6) {
            Text(emoji).font(.system(size: 26))
            Text(value)
                .font(.sfProDisplay(28, weight: .bold))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())
            Text(caption)
                .font(.sfProDisplay(13, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
    }
}
