import SwiftUI
import StoreKit

// MARK: - Design tokens

private enum PaywallColors {
    static let background = Color(.systemBackground)
    static let cardBg     = Color(.secondarySystemBackground)
    static let separator  = Color.primary.opacity(0.12)
    /// The app's violet accent (matches the landing site's `#7c4df0`).
    static let accent     = Color(hex: "7C4DF0")
    static let accentDeep = Color(hex: "5B2FD6")
}

// MARK: - Plan / period model

private enum PaywallPlan: String, CaseIterable, Identifiable {
    case premium, family, max
    var id: String { rawValue }

    var title: String {
        switch self {
        case .premium: return "Premium"
        case .family:  return "Family"
        case .max:     return "Max"
        }
    }

    var badge: String? {
        self == .max ? "MAX" : nil
    }

    var periods: [PaywallPeriod] {
        switch self {
        case .premium: return [.monthly, .annual, .forever]
        case .family:  return [.monthly, .annual]
        case .max:     return [.monthly]
        }
    }

    var features: [String] {
        switch self {
        case .premium:
            return [
                "Безлимит задач и привычек",
                "30 AI-проверок фото в месяц",
                "AI-коуч и планировщик целей",
                "Полная история и статистика",
                "Заморозка серии 1 раз в неделю"
            ]
        case .family:
            return [
                "Всё из Premium для 5 человек",
                "Семейный рейтинг",
                "Код приглашения для семьи"
            ]
        case .max:
            return [
                "Всё из Premium",
                "100 AI-проверок фото в месяц",
                "Расширенные лимиты AI-коуча и планера",
                "Коннекторы Max: Strava, Whoop, Notion, Google Docs, Google Drive, Gmail",
                "Приоритетная обработка"
            ]
        }
    }
}

private enum PaywallPeriod: String, CaseIterable, Identifiable {
    case monthly, annual, forever
    var id: String { rawValue }

    var title: String {
        switch self {
        case .monthly: return "Месяц"
        case .annual:  return "Год"
        case .forever: return "Навсегда"
        }
    }
}

// MARK: - Paywall

struct PremiumView: View {
    @State private var store = StoreService.shared
    @Environment(\.dismiss) private var dismiss

    @State private var selectedPlan: PaywallPlan = .premium
    @State private var selectedPeriod: PaywallPeriod = .monthly

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                header

                if store.currentPlan != .free {
                    currentPlanBanner
                }

                planSelector

                periodSelector

                featureList

                if let err = store.errorMessage {
                    Text(err)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                ctaButton

                restoreButton

                footer
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .background(PaywallColors.background.ignoresSafeArea())
        .navigationTitle("Подписка")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Haptics.tap()
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
            }
        }
        .onAppear {
            AnalyticsService.shared.track(.premiumPaywallShown)
            // Make sure the chosen plan always has a valid period selected.
            if !selectedPlan.periods.contains(selectedPeriod) {
                selectedPeriod = selectedPlan.periods.first ?? .monthly
            }
        }
        .onChange(of: selectedPlan) { _, newPlan in
            Haptics.selection()
            if !newPlan.periods.contains(selectedPeriod) {
                selectedPeriod = newPlan.periods.first ?? .monthly
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [PaywallColors.accent, PaywallColors.accentDeep],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 64, height: 64)
                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(.top, 8)

            Text("The Challenge Premium")
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text("AI проверяет твои привычки по фото")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Current plan banner

    private var currentPlanBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundStyle(PaywallColors.accent)
            Text("Твой план: \(store.currentPlan.displayName)")
                .font(.subheadline.weight(.semibold))
            Spacer()
            Text("Улучшить")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(PaywallColors.cardBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: Plan selector

    private var planSelector: some View {
        HStack(spacing: 10) {
            ForEach(PaywallPlan.allCases) { plan in
                planCard(plan)
            }
        }
    }

    private func planCard(_ plan: PaywallPlan) -> some View {
        let isSelected = selectedPlan == plan
        return Button {
            selectedPlan = plan
        } label: {
            VStack(spacing: 6) {
                if let badge = plan.badge {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            Capsule().fill(.white.opacity(isSelected ? 0.25 : 0.15))
                        )
                        .foregroundStyle(isSelected ? .white : PaywallColors.accent)
                }
                Text(plan.title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(isSelected && plan == .max ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(planCardBackground(plan, isSelected: isSelected))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(
                        isSelected ? PaywallColors.accent.opacity(plan == .max ? 0 : 0.6) : PaywallColors.separator,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.haptic(.light))
    }

    private func planCardBackground(_ plan: PaywallPlan, isSelected: Bool) -> AnyShapeStyle {
        if plan == .max && isSelected {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [PaywallColors.accent, PaywallColors.accentDeep],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        }
        if isSelected {
            return AnyShapeStyle(PaywallColors.accent.opacity(0.12))
        }
        return AnyShapeStyle(PaywallColors.cardBg)
    }

    // MARK: Period selector

    private var periodSelector: some View {
        HStack(spacing: 10) {
            ForEach(selectedPlan.periods) { period in
                periodPill(period)
            }
        }
    }

    private func periodPill(_ period: PaywallPeriod) -> some View {
        let isSelected = selectedPeriod == period
        return Button {
            Haptics.selection()
            selectedPeriod = period
        } label: {
            VStack(spacing: 4) {
                Text(period.title)
                    .font(.subheadline.weight(.semibold))
                if let badge = savingsBadge(for: period) {
                    Text(badge)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(isSelected ? .white : PaywallColors.accent)
                }
                Text(priceLabel(for: selectedPlan, period: period))
                    .font(.caption)
                    .foregroundStyle(isSelected ? .white.opacity(0.85) : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(isSelected ? PaywallColors.accent : PaywallColors.cardBg)
            )
            .foregroundStyle(isSelected ? .white : .primary)
        }
        .buttonStyle(.haptic(.light))
    }

    // MARK: Feature list

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Что входит в \(selectedPlan.title)")
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                ForEach(selectedPlan.features, id: \.self) { feature in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(PaywallColors.accent)
                            .font(.system(size: 18))
                        Text(feature)
                            .font(.subheadline)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(PaywallColors.cardBg)
        )
    }

    // MARK: CTA

    private var ctaButton: some View {
        Button {
            Haptics.tap()
            Task {
                let success = await store.purchase(productID: productID(for: selectedPlan, period: selectedPeriod))
                if success {
                    Haptics.success()
                    dismiss()
                }
            }
        } label: {
            Group {
                if store.isPurchasing {
                    ProgressView().tint(.white)
                } else {
                    Text("Оформить -- \(priceLabel(for: selectedPlan, period: selectedPeriod))")
                        .fontWeight(.semibold)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 52)
        }
        .buttonStyle(.borderedProminent)
        .tint(PaywallColors.accent)
        .disabled(store.isPurchasing)
    }

    private var restoreButton: some View {
        Button {
            Haptics.tap()
            Task { await store.restore() }
        } label: {
            Text("Восстановить покупки")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .disabled(store.isPurchasing)
    }

    private var footer: some View {
        Text("Подписка продлевается автоматически. Отменить можно в любой момент в настройках App Store.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 8)
    }

    // MARK: - Pricing helpers

    /// Maps a plan + period to the StoreKit product ID.
    private func productID(for plan: PaywallPlan, period: PaywallPeriod) -> String {
        switch (plan, period) {
        case (.premium, .monthly): return Constants.Store.premiumMonthlyID
        case (.premium, .annual):  return Constants.Store.premiumAnnualID
        case (.premium, .forever): return Constants.Store.premiumForeverID
        case (.family, .monthly):  return Constants.Store.familyMonthlyID
        case (.family, .annual):   return Constants.Store.familyAnnualID
        case (.max, .monthly):     return Constants.Store.maxMonthlyID
        default:                   return Constants.Store.premiumMonthlyID
        }
    }

    /// Display price for a plan + period, falling back to hardcoded prices
    /// when the StoreKit product hasn't loaded yet.
    private func priceLabel(for plan: PaywallPlan, period: PaywallPeriod) -> String {
        let id = productID(for: plan, period: period)
        if let price = store.product(for: id)?.displayPrice {
            return price
        }
        return fallbackPrice(for: plan, period: period)
    }

    private func fallbackPrice(for plan: PaywallPlan, period: PaywallPeriod) -> String {
        switch (plan, period) {
        case (.premium, .monthly): return "$4.99/мес"
        case (.premium, .annual):  return "$39.99/год"
        case (.premium, .forever): return "$99.99 навсегда"
        case (.family, .monthly):  return "$9.99/мес"
        case (.family, .annual):   return "$79.99/год"
        case (.max, .monthly):     return "$19.99/мес"
        default:                   return ""
        }
    }

    /// Savings badge for annual periods, computed from loaded product prices
    /// when available, otherwise from the fallback prices above.
    private func savingsBadge(for period: PaywallPeriod) -> String? {
        guard period == .annual else { return nil }

        let monthlyID = productID(for: selectedPlan, period: .monthly)
        let annualID = productID(for: selectedPlan, period: .annual)

        let monthlyPrice = store.product(for: monthlyID)?.price
        let annualPrice = store.product(for: annualID)?.price

        let monthly: Double
        let annual: Double
        if let monthlyPrice, let annualPrice {
            monthly = NSDecimalNumber(decimal: monthlyPrice).doubleValue
            annual = NSDecimalNumber(decimal: annualPrice).doubleValue
        } else {
            switch selectedPlan {
            case .premium: monthly = 4.99; annual = 39.99
            case .family:  monthly = 9.99; annual = 79.99
            case .max:     return nil
            }
        }

        guard monthly > 0 else { return nil }
        let yearlyAtMonthlyRate = monthly * 12
        guard yearlyAtMonthlyRate > 0 else { return nil }
        let savingsPercent = Int(((yearlyAtMonthlyRate - annual) / yearlyAtMonthlyRate * 100).rounded())
        guard savingsPercent > 0 else { return nil }
        return "выгоднее на \(savingsPercent)%"
    }
}

#Preview {
    NavigationStack {
        PremiumView()
    }
}
