import SwiftUI

/// Detail sheet opened by tapping the "Сегодня, <date>" header on Home.
/// Shows the user's current streak, best streak and the streak-freeze wallet,
/// plus a one-tap action to freeze yesterday when the run is at risk.
struct StreakDetailView: View {
    let vm: ActivitiesViewModel

    @Environment(\.dismiss) private var dismiss
    @State private var isFreezing = false

    private var streak: Int { vm.globalStreakCurrent }
    private var best: Int { vm.globalStreakBest }
    private var freezes: Int { vm.freezesAvailable }
    private var canFreezeYesterday: Bool {
        vm.yesterdayFreezable && vm.freezesAvailable > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    flameHeader

                    HStack(spacing: 12) {
                        StatTile(emoji: "🏆",
                                 value: "\(best)",
                                 caption: "Лучшая серия")
                        StatTile(emoji: "🧊",
                                 value: "\(freezes)",
                                 caption: "Заморозки")
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
            Image(systemName: streak > 0 ? "flame.fill" : "flame")
                .font(.system(size: 64, weight: .semibold))
                .foregroundStyle(streak > 0 ? .orange : .secondary)
                .symbolEffect(.bounce, value: streak)

            Text("\(streak)")
                .font(.sfProDisplay(56, weight: .bold))
                .foregroundStyle(.primary)
                .contentTransition(.numericText())

            Text(streak == 1 ? "день подряд" : "дней подряд")
                .font(.sfProDisplay(16, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
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
                    Text("Заморозка спасает серию за пропущенный день -- он засчитывается, и серия не прерывается. Новые заморозки начисляются за каждые 7 дней лучшей серии.")
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
