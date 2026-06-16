import SwiftUI
import StoreKit

// MARK: - Design tokens

private enum PaywallStyle {
    static let bg          = Color.black
    static let accentRed   = Color(red: 1, green: 0.039, blue: 0.039)
    static let subscribe   = Color(hex: "0048E2")
    static let cardWhite   = Color.white.opacity(0.06)
    static let cardBorder  = Color.white.opacity(0.12)
    static let subtitle    = Color.white.opacity(0.7)
    static let heroHeight: CGFloat = 280
}

private struct PaywallFeature: Identifiable {
    let id = UUID()
    let icon: String
    let text: String
}

/// A purchasable option backed by a real StoreKit product id.
private struct PaywallOption: Identifiable {
    let id: String          // product id
    let title: String
    let period: String      // "/год", "/мес", ""
    let monthlyForSavings: String?  // monthly product id to compute the savings badge
}

// MARK: - Paywall (dark)
// Struct name kept as `PremiumView` -- every call site presents this.

struct PremiumView: View {
    @State private var store = StoreService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selected: String = Constants.Store.premiumAnnualID

    private let features: [PaywallFeature] = [
        .init(icon: "infinity",            text: "Безлимит задач и привычек"),
        .init(icon: "checkmark.seal",      text: "Больше AI-проверок фото"),
        .init(icon: "sparkles",            text: "AI-коуч и планировщик целей"),
        .init(icon: "chart.xyaxis.line",   text: "Полная статистика и история"),
        .init(icon: "snowflake",           text: "Заморозка серии и бонусы")
    ]

    private var proOptions: [PaywallOption] {
        [
            .init(id: Constants.Store.premiumAnnualID, title: "Год", period: "/год",
                  monthlyForSavings: Constants.Store.premiumMonthlyID),
            .init(id: Constants.Store.premiumMonthlyID, title: "Месяц", period: "/мес",
                  monthlyForSavings: nil),
            .init(id: Constants.Store.premiumForeverID, title: "Навсегда", period: "",
                  monthlyForSavings: nil)
        ]
    }

    private var familyOptions: [PaywallOption] {
        [
            .init(id: Constants.Store.familyAnnualID, title: "Год", period: "/год",
                  monthlyForSavings: Constants.Store.familyMonthlyID),
            .init(id: Constants.Store.familyMonthlyID, title: "Месяц", period: "/мес",
                  monthlyForSavings: nil)
        ]
    }

    private var maxOptions: [PaywallOption] {
        [
            .init(id: Constants.Store.maxAnnualID, title: "Год", period: "/год",
                  monthlyForSavings: Constants.Store.maxMonthlyID),
            .init(id: Constants.Store.maxMonthlyID, title: "Месяц", period: "/мес",
                  monthlyForSavings: nil)
        ]
    }

    var body: some View {
        ZStack(alignment: .top) {
            PaywallStyle.bg.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    hero
                    VStack(alignment: .leading, spacing: 16) {
                        Text("reInspire")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(.white)

                        Text("🚀 Перейди на Премиум -- успевай больше")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundColor(.white)
                            .fixedSize(horizontal: false, vertical: true)

                        featureList.padding(.top, 4)

                        sectionLabel("reInspire Pro")
                        ForEach(proOptions) { optionRow($0) }

                        sectionLabel("reInspire Max").padding(.top, 4)
                        Text("Всё из Pro + максимум AI-проверок и коннектор Strava.")
                            .font(.system(size: 14))
                            .foregroundColor(PaywallStyle.subtitle)
                        ForEach(maxOptions) { optionRow($0) }

                        sectionLabel("reInspire Family").padding(.top, 4)
                        Text("Премиум для всей семьи (до 5 человек).")
                            .font(.system(size: 14))
                            .foregroundColor(PaywallStyle.subtitle)
                        ForEach(familyOptions) { optionRow($0) }

                        if let err = store.errorMessage {
                            Text(err).font(.footnote).foregroundColor(PaywallStyle.accentRed)
                        }

                        subscribeButton.padding(.top, 8)
                        legal.padding(.bottom, 24)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .readableWidth(560)
                }
            }

            closeButton
        }
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { AnalyticsService.shared.track(.premiumPaywallShown) }
    }

    // MARK: Hero

    private var hero: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [Color(hex: "1B3A8F"), Color(hex: "0A1838")],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: PaywallStyle.heroHeight)
            .overlay {
                Image("icon_preview_blue")
                    .resizable().scaledToFit()
                    .frame(width: 110, height: 110)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    .shadow(color: .black.opacity(0.4), radius: 20, y: 10)
            }

            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.6), location: 0.65),
                    .init(color: .black, location: 1)
                ],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: PaywallStyle.heroHeight)
        }
        .frame(height: PaywallStyle.heroHeight)
        .clipped()
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 22, weight: .semibold))
            .foregroundColor(.white)
    }

    // MARK: Features

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(features) { f in
                HStack(spacing: 12) {
                    Image(systemName: f.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(PaywallStyle.accentRed)
                        .frame(width: 22)
                    Text(f.text)
                        .font(.system(size: 16))
                        .foregroundColor(.white.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: Plan option row

    private func optionRow(_ option: PaywallOption) -> some View {
        let isSelected = selected == option.id
        return Button {
            Haptics.selection(); selected = option.id
        } label: {
            HStack(spacing: 10) {
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? PaywallStyle.accentRed : Color.white.opacity(0.3), lineWidth: 2)
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle().fill(PaywallStyle.accentRed).frame(width: 14, height: 14)
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundColor(.white)
                    }
                }
                Text(option.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                if let badge = savingsBadge(for: option) {
                    Text(badge)
                        .font(.system(size: 13))
                        .foregroundColor(PaywallStyle.accentRed)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(PaywallStyle.accentRed.opacity(0.12)))
                        .overlay(Capsule().strokeBorder(PaywallStyle.accentRed.opacity(0.5), lineWidth: 1))
                }
                Spacer()
                HStack(spacing: 0) {
                    Text(priceText(for: option.id))
                        .font(.system(size: 16, weight: .semibold)).foregroundColor(.white)
                    Text(option.period)
                        .font(.system(size: 16)).foregroundColor(.white.opacity(0.7))
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 60)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? PaywallStyle.accentRed.opacity(0.05) : PaywallStyle.cardWhite)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(isSelected ? PaywallStyle.accentRed : PaywallStyle.cardBorder, lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
    }

    // MARK: Subscribe + legal

    private var subscribeButton: some View {
        Button {
            Haptics.tap()
            Task {
                if await store.purchase(productID: selected) {
                    Haptics.success(); dismiss()
                }
            }
        } label: {
            Group {
                if store.isPurchasing { ProgressView().tint(.white) }
                else { Text("Подписаться").font(.system(size: 17, weight: .semibold)) }
            }
            .foregroundColor(.white)
            .frame(maxWidth: .infinity).frame(height: 50)
            .background(RoundedRectangle(cornerRadius: 12).fill(PaywallStyle.subscribe))
        }
        .disabled(store.isPurchasing)
    }

    private var legal: some View {
        VStack(spacing: 10) {
            Button { Haptics.tap(); Task { await store.restore() } } label: {
                Text("Восстановить покупки")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(.white.opacity(0.85))
            }
            Text("Подписка продлевается автоматически. Отменить можно в любой момент в App Store.")
                .font(.system(size: 12))
                .foregroundColor(PaywallStyle.subtitle)
                .multilineTextAlignment(.center)
            HStack(spacing: 16) {
                Link("Условия", destination: URL(string: "https://thechallenges.app/terms.html")!)
                Link("Конфиденциальность", destination: URL(string: "https://thechallenges.app/privacy.html")!)
            }
            .font(.system(size: 12))
            .foregroundColor(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private var closeButton: some View {
        HStack {
            Button { Haptics.tap(); dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(.black.opacity(0.35)))
            }
            Spacer()
        }
        .padding(.leading, 16)
        .padding(.top, 56)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Pricing helpers

    private func priceText(for productID: String) -> String {
        if let p = store.product(for: productID)?.displayPrice { return p }
        // Fallbacks until StoreKit products load.
        switch productID {
        case Constants.Store.premiumAnnualID:  return "$39.99"
        case Constants.Store.premiumMonthlyID: return "$4.99"
        case Constants.Store.premiumForeverID: return "$99.99"
        case Constants.Store.familyAnnualID:   return "$79.99"
        case Constants.Store.familyMonthlyID:  return "$9.99"
        case Constants.Store.maxAnnualID:      return "$129.99"
        case Constants.Store.maxMonthlyID:     return "$14.99"
        default:                               return "--"
        }
    }

    /// "Выгода X%" for a yearly option vs 12× its monthly counterpart.
    private func savingsBadge(for option: PaywallOption) -> String? {
        guard let monthlyID = option.monthlyForSavings else { return nil }
        let annual = store.product(for: option.id)?.price
        let monthly = store.product(for: monthlyID)?.price
        let a: Double, m: Double
        if let annual, let monthly {
            a = NSDecimalNumber(decimal: annual).doubleValue
            m = NSDecimalNumber(decimal: monthly).doubleValue
        } else {
            // Fallback figures matching priceText.
            a = option.id == Constants.Store.familyAnnualID ? 79.99 : 39.99
            m = option.id == Constants.Store.familyAnnualID ? 9.99 : 4.99
        }
        guard m > 0 else { return nil }
        let pct = Int(((m * 12 - a) / (m * 12) * 100).rounded())
        return pct > 0 ? "Выгода \(pct)%" : nil
    }
}

#Preview {
    PremiumView()
}
