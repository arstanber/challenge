import SwiftUI

// MARK: - Evening Recap
//
// The evening counterpart to the Morning Brief. Morning Brief opens the day
// (greeting + top tasks + tip); Evening Recap closes it: what actually got
// done, one reflective prompt, and the focus for tomorrow.
//
// This file is presentational + the wire model. The data path (edge function
// `evening-recap`, `AICoachService.eveningRecap()`, rate limiting) lives in the
// service layer -- these views never call the network themselves.
//
// Palette: the morning surfaces use brand blue (4580FF). Evening deliberately
// shifts to the brand violet (7C4DF0) so the two moments read as different
// halves of the same day at a glance.

// MARK: - Model

/// Server payload for the evening recap. `error` mirrors `MorningBrief`: the
/// edge function degrades to a localized fallback rather than failing, so a
/// non-nil `error` is diagnostic only and never blocks rendering.
struct EveningRecap: Decodable, Identifiable {
    /// Stable per-day identity so the sheet can be presented with `.sheet(item:)`.
    var id: String { headline }

    let headline: String        // one-liner summing the day up
    let wins: [String]          // up to 3 things the user actually completed
    let reflection: String      // a single open question to sit with
    let tomorrowFocus: [String] // up to 3 titles to carry into tomorrow
    let completed: Int          // tasks completed today
    let total: Int              // tasks scheduled today
    let error: String?
    let remaining: Int?

    private enum CodingKeys: String, CodingKey {
        case headline, wins, reflection, tomorrowFocus, completed, total, error, remaining
    }

    /// 0...1, guarded against a zero/negative denominator from the server.
    var progress: Double {
        guard total > 0 else { return 0 }
        return min(1, max(0, Double(completed) / Double(total)))
    }
}

// MARK: - Palette

private enum RecapPalette {
    static let accent = Color(hex: "7C4DF0")
    static let accentSoft = Color(hex: "9B7BF5")
    /// Card fill that stays legible in both appearances -- unlike a hardcoded
    /// `Color.black.opacity(...)`, which disappears on a dark background.
    static let cardFill = Color(.secondarySystemBackground)
    static let pageBg = Color(.systemBackground)
}

// MARK: - Home banner

/// Compact entry point shown on HomeView in the evening. Mirrors the shape of
/// `AICoachBanner` so the two never feel like different apps, but uses semantic
/// foreground colors so it stays readable in dark mode.
struct EveningRecapBanner: View {
    let recap: EveningRecap
    let onExpand: () -> Void

    var body: some View {
        Button(action: onExpand) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(RecapPalette.accent.opacity(0.12))
                        .frame(width: 44, height: 44)
                    RecapRing(progress: recap.progress, lineWidth: 3)
                        .frame(width: 36, height: 36)
                    Text("🌙").font(.system(size: 17))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(recap.headline)
                        .font(.manrope(.bold, size: 14))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(Self.subtitle(completed: recap.completed, total: recap.total))
                        .font(.manrope(.medium, size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(RecapPalette.accent.opacity(0.07))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(RecapPalette.accent.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.haptic)
        .accessibilityLabel(Self.accessibilityLabel(recap: recap))
        .accessibilityHint(AppLanguage.t(
            en: "Opens your evening recap",
            ru: "Открывает итоги дня",
            de: "Öffnet deinen Tagesrückblick",
            kk: "Күн қорытындысын ашады",
            fr: "Ouvre ton bilan du soir",
            ar: "يفتح ملخّص يومك"
        ))
    }

    private static func subtitle(completed: Int, total: Int) -> String {
        let template = AppLanguage.t(
            en: "%d of %d done today",
            ru: "%d из %d за сегодня",
            de: "%d von %d heute geschafft",
            kk: "Бүгін %d / %d орындалды",
            fr: "%d sur %d aujourd'hui",
            ar: "%d من %d اليوم"
        )
        return String(format: template, completed, total)
    }

    private static func accessibilityLabel(recap: EveningRecap) -> String {
        "\(recap.headline). \(subtitle(completed: recap.completed, total: recap.total))"
    }
}

// MARK: - Full sheet

struct EveningRecapSheet: View {
    @Environment(\.dismiss) private var dismiss
    let recap: EveningRecap

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    if !recap.wins.isEmpty {
                        RecapCard(
                            emoji: "✅",
                            title: AppLanguage.t(
                                en: "What you pulled off",
                                ru: "Что удалось",
                                de: "Was du geschafft hast",
                                kk: "Не тындырдың",
                                fr: "Ce que tu as accompli",
                                ar: "ما أنجزته"
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(recap.wins, id: \.self) { win in
                                    HStack(alignment: .top, spacing: 10) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(Color(hex: "2FB873"))
                                            .padding(.top, 1)
                                        Text(win)
                                            .font(.manrope(.medium, size: 14))
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }
                        }
                        .appearEffect(delay: 0.05)
                    }

                    RecapCard(
                        emoji: "🪞",
                        title: AppLanguage.t(
                            en: "Sit with this",
                            ru: "Подумай об этом",
                            de: "Denk darüber nach",
                            kk: "Осыны ойлан",
                            fr: "Prends un instant",
                            ar: "تأمّل في هذا"
                        )
                    ) {
                        Text(recap.reflection)
                            .font(.manrope(.medium, size: 15))
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .appearEffect(delay: 0.15)

                    if !recap.tomorrowFocus.isEmpty {
                        RecapCard(
                            emoji: "🌅",
                            title: AppLanguage.t(
                                en: "Carry into tomorrow",
                                ru: "Взять в завтра",
                                de: "Nimm es mit in morgen",
                                kk: "Ертеңге ал",
                                fr: "À emporter demain",
                                ar: "خُذه إلى الغد"
                            )
                        ) {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(recap.tomorrowFocus, id: \.self) { item in
                                    HStack(alignment: .top, spacing: 10) {
                                        Circle()
                                            .fill(RecapPalette.accent)
                                            .frame(width: 6, height: 6)
                                            .padding(.top, 7)
                                        Text(item)
                                            .font(.manrope(.medium, size: 14))
                                            .foregroundStyle(.primary)
                                    }
                                }
                            }
                        }
                        .appearEffect(delay: 0.25)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 40)
                .readableWidth()
            }
        }
        .background(RecapPalette.pageBg)
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(AppLanguage.t(
                        en: "Evening recap 🌙",
                        ru: "Итоги дня 🌙",
                        de: "Tagesrückblick 🌙",
                        kk: "Күн қорытындысы 🌙",
                        fr: "Bilan du soir 🌙",
                        ar: "ملخّص المساء 🌙"
                    ))
                    .font(.manrope(.extraBold, size: 24))
                    .foregroundStyle(.primary)

                    Text(recap.headline)
                        .font(.manrope(.medium, size: 14))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(Color.primary.opacity(0.07)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLanguage.t(
                    en: "Close", ru: "Закрыть", de: "Schließen",
                    kk: "Жабу", fr: "Fermer", ar: "إغلاق"
                ))
            }

            scoreRow
        }
        .padding(.horizontal, 22)
        .padding(.top, 24)
        .padding(.bottom, 20)
        .readableWidth()
    }

    /// Ring + count. The ring is the one moment of brand colour in the sheet;
    /// everything else stays semantic so dark mode needs no special-casing.
    private var scoreRow: some View {
        HStack(spacing: 16) {
            ZStack {
                RecapRing(progress: recap.progress, lineWidth: 6)
                    .frame(width: 64, height: 64)
                Text("\(Int((recap.progress * 100).rounded()))%")
                    .font(.manrope(.extraBold, size: 15))
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(AppLanguage.t(
                    en: "Today's completion",
                    ru: "Выполнено сегодня",
                    de: "Heute erledigt",
                    kk: "Бүгін орындалды",
                    fr: "Terminé aujourd'hui",
                    ar: "أُنجز اليوم"
                ))
                .font(.manrope(.medium, size: 13))
                .foregroundStyle(.secondary)

                Text("\(recap.completed) / \(recap.total)")
                    .font(.manrope(.extraBold, size: 22))
                    .foregroundStyle(.primary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(RecapPalette.cardFill)
        )
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Pieces

/// Thin progress ring. Track uses `Color.primary.opacity` rather than a fixed
/// grey so it keeps contrast against both light and dark backgrounds.
private struct RecapRing: View {
    let progress: Double
    var lineWidth: CGFloat = 6

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.10), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, progress))
                .stroke(
                    AngularGradient(
                        colors: [RecapPalette.accent, RecapPalette.accentSoft, RecapPalette.accent],
                        center: .center
                    ),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeOut(duration: 0.6), value: progress)
        }
        .accessibilityHidden(true)
    }
}

private struct RecapCard<Content: View>: View {
    let emoji: String
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text(emoji).font(.system(size: 18))
                Text(title)
                    .font(.manrope(.bold, size: 16))
                    .foregroundStyle(.primary)
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(RecapPalette.cardFill)
        )
    }
}

// MARK: - Preview

#Preview("Sheet") {
    EveningRecapSheet(recap: EveningRecap(
        headline: "Сильный день: три из четырёх закрыты.",
        wins: ["Утренняя зарядка", "Прочитать 20 страниц", "Английский 30 минут"],
        reflection: "Что сегодня далось легче, чем ты ожидал, и почему?",
        tomorrowFocus: ["Пробежка 5 км", "Созвон с командой"],
        completed: 3,
        total: 4,
        error: nil,
        remaining: 9
    ))
}
