import SwiftUI
import UIKit

// MARK: - App theme (used by RootView via @AppStorage("appTheme"))

enum AppColorTheme: String, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var title: String {
        switch self {
        case .system: return "Системная"
        case .light:  return "Светлая"
        case .dark:   return "Тёмная"
        }
    }
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var auth = AuthService.shared
    @State private var cloudSync = CloudSyncService.shared

    // Global
    @AppStorage("appTheme") private var appTheme = AppColorTheme.light.rawValue
    @AppStorage("timeFormat") private var timeFormat = "24 часа"
    @AppStorage("units") private var units = "Метр. (км, мл)"
    @AppStorage("weekStart") private var weekStart = "Понедельник"
    @AppStorage(Haptics.enabledKey) private var hapticsEnabled = true
    @AppStorage(AppPrefs.Key.zoomerMode) private var zoomerMode = false
    // Habits
    // Default true: done tasks collect at the bottom (HomeView reads this too).
    @AppStorage("groupCompleted") private var groupCompleted = true
    @AppStorage("strictMode") private var strictMode = true
    @AppStorage("requirePhotoVerification") private var requirePhoto = true

    @State private var showPremium = false
    @State private var showAppIcon = false
    @State private var showHallOfFame = false
    @State private var showSignOut = false
    @State private var showTelegramLink = false
    @State private var showConnectors = false
    @State private var showDuels = false
    @State private var showLeaderboard = false
    @State private var showReferral = false
    @State private var showFamily = false
    @State private var showStatistics = false

    private let blue = Color(hex: "0A84FF")

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 26) {
                    // Upsell only makes sense for free users; isPremium also
                    // covers temporary referral PRO (pro_until).
                    if auth.currentUser?.isPremium != true {
                        premiumCard
                    }
                    personalSection
                    globalSection
                    habitsSection
                    syncSection
                    connectionsSection
                    infoSection
                    accountSection
                    footer
                }
                .padding(.horizontal, 18)
                .padding(.top, 64)
                .padding(.bottom, 50)
                .readableWidth()
            }

            header
        }
        .sheet(isPresented: $showPremium) {
            NavigationStack { PremiumView() }
        }
        .sheet(isPresented: $showAppIcon) {
            AppIconPickerView()
        }
        .sheet(isPresented: $showTelegramLink) {
            NavigationStack { TelegramLinkView() }
        }
        .sheet(isPresented: $showConnectors) {
            NavigationStack { ConnectorsView() }
        }
        .sheet(isPresented: $showDuels) {
            NavigationStack { DuelsView().environment(auth) }
        }
        .sheet(isPresented: $showLeaderboard) {
            NavigationStack { LeaderboardView().environment(auth) }
        }
        .sheet(isPresented: $showReferral) {
            NavigationStack { ReferralView().environment(auth) }
        }
        .sheet(isPresented: $showFamily) {
            NavigationStack { FamilyView().environment(auth) }
        }
        .sheet(isPresented: $showStatistics) {
            StatisticsView()
        }
        .fullScreenCover(isPresented: $showHallOfFame) {
            ZStack(alignment: .topTrailing) {
                GamificationView()
                Button { Haptics.tap(); showHallOfFame = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.primary.opacity(0.1)))
                }
                .padding(20)
            }
        }
        .confirmationDialog("Выйти из аккаунта?", isPresented: $showSignOut, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) {
                Haptics.warning(); dismiss(); AuthService.shared.signOut()
            }
            Button("Отмена", role: .cancel) {}
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack {
            Text("Настройки")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
            HStack {
                Spacer()
                Button { Haptics.tap(); dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.primary.opacity(0.1)))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    // MARK: Premium card

    private var premiumCard: some View {
        Button { Haptics.tap(); showPremium = true } label: {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Перейдите на Премиум")
                        .font(.system(size: 23, weight: .bold))
                        .foregroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Откройте неограниченные привычки")
                        .font(.system(size: 16))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Перейти")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 26)
                        .padding(.vertical, 12)
                        .background(Capsule().fill(blue))
                        .padding(.top, 6)
                }
                Spacer(minLength: 8)
                Image("icon_preview_blue")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 92, height: 92)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .offset(x: 6)
            }
            .padding(20)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Sections

    private var personalSection: some View {
        SettingsSection(title: "Личное") {
            SettingsRow(icon: "trophy", title: "Зал славы", trailing: .chevron) {
                Haptics.tap(); showHallOfFame = true
            }
            SettingsDivider()
            SettingsRow(icon: "chart.xyaxis.line", title: "Статистика", trailing: .chevron) {
                Haptics.tap(); showStatistics = true
            }
            SettingsDivider()
            SettingsRow(icon: "person.3", title: "Семейная группа", trailing: .chevron) {
                Haptics.tap(); showFamily = true
            }
            SettingsDivider()
            SettingsRow(icon: "figure.fencing", title: "Дуэли с друзьями", trailing: .chevron) {
                Haptics.tap(); showDuels = true
            }
            SettingsDivider()
            SettingsRow(icon: "chart.bar.fill", title: "Рейтинг по сериям", trailing: .chevron) {
                Haptics.tap(); showLeaderboard = true
            }
            SettingsDivider()
            SettingsRow(icon: "gift.fill", title: "Пригласить друга", badge: "PRO дни", trailing: .chevron) {
                Haptics.tap(); showReferral = true
            }
        }
    }

    private var globalSection: some View {
        SettingsSection(title: "Глобальные настройки") {
            SettingsRow(icon: "app", title: "Значок приложения", badge: "PRO", trailing: .chevron) {
                Haptics.tap()
                // Paywall for free users, the actual picker for subscribers
                // (isPremium also covers temporary referral PRO).
                if auth.currentUser?.isPremium == true {
                    showAppIcon = true
                } else {
                    showPremium = true
                }
            }
            SettingsDivider()
            SettingsRow(icon: "globe", title: "Язык", value: "Русский", trailing: .chevron) {
                Haptics.tap(); openSystemSettings()
            }
            SettingsDivider()
            SettingsMenuRow(icon: "circle.lefthalf.filled", title: "Тема",
                            selection: $appTheme, options: AppColorTheme.allCases.map(\.rawValue),
                            display: { AppColorTheme(rawValue: $0)?.title ?? $0 })
            SettingsDivider()
            SettingsMenuRow(icon: "clock", title: "Формат времени",
                            selection: $timeFormat, options: ["24 часа", "12 часов"])
            SettingsDivider()
            SettingsMenuRow(icon: "chart.bar", title: "Единицы",
                            selection: $units, options: ["Метр. (км, мл)", "Имп. (мили)"])
            SettingsDivider()
            SettingsMenuRow(icon: "calendar", title: "Начало недели",
                            selection: $weekStart, options: ["Понедельник", "Воскресенье"])
            SettingsDivider()
            SettingsToggleRow(
                icon: "iphone.radiowaves.left.and.right",
                title: "Вибрация",
                subtitle: "Тактильный отклик при нажатиях и действиях.",
                isOn: $hapticsEnabled
            )
            SettingsDivider()
            SettingsToggleRow(
                icon: "theatermasks",
                title: "Режим зумера",
                subtitle: "Пуши начнут общаться с тобой на сленге: стрики, пруфы, вайб. Без кринжа (почти).",
                isOn: $zoomerMode
            )
        }
    }

    private var habitsSection: some View {
        SettingsSection(title: "Настройки привычек") {
            SettingsToggleRow(
                icon: "camera",
                title: "Требовать фото",
                subtitle: "Каждое задание нужно подтвердить фотографией. Выключите, чтобы отмечать без фото.",
                isOn: $requirePhoto
            )
            SettingsDivider()
            SettingsToggleRow(icon: "arrow.down.circle", title: "Группировать выполненные", isOn: $groupCompleted)
            SettingsDivider()
            SettingsRow(icon: "bell", title: "Уведомления", trailing: .chevron) {
                Haptics.tap(); openSystemSettings()
            }
            SettingsDivider()
            SettingsToggleRow(
                icon: "flame",
                title: "Строгий режим",
                subtitle: "Привычка засчитывается только при полном достижении цели (например, 10 000 из 10 000 шагов).",
                isOn: $strictMode
            )
        }
    }

    private var syncSection: some View {
        SettingsSection(title: "Синхронизация") {
            SettingsStatusRow(
                icon: "icloud",
                title: "iCloud",
                statusText: cloudSync.status.title,
                statusColor: cloudSync.status == .synced ? Color(hex: "30D158") : .secondary,
                subtitle: cloudSync.status == .synced
                    ? "Настройки синхронизируются через iCloud. Чтобы отключить, выключите iCloud для reInspire в системных настройках."
                    : "Войдите в iCloud в системных настройках, чтобы синхронизировать настройки между устройствами."
            )
        }
    }

    private var connectionsSection: some View {
        SettingsSection(title: "Связи") {
            SettingsRow(icon: "paperplane", title: "Telegram бот", trailing: .chevron) {
                Haptics.tap(); showTelegramLink = true
            }
            SettingsDivider()
            SettingsRow(icon: "antenna.radiowaves.left.and.right", title: "Коннекторы", trailing: .chevron) {
                Haptics.tap(); showConnectors = true
            }
        }
    }

    private var infoSection: some View {
        SettingsSection(title: "Инфо") {
            SettingsLinkRow(icon: "questionmark.circle", title: "FAQ",
                            url: URL(string: "https://thechallenges.app/support.html")!)
            SettingsDivider()
            SettingsLinkRow(icon: "sparkles", title: "Что нового",
                            url: URL(string: "https://thechallenges.app/features.html")!)
            SettingsDivider()
            SettingsShareRow(icon: "square.and.arrow.up", title: "Поделиться приложением",
                             url: URL(string: "https://thechallenges.app")!)
            SettingsDivider()
            SettingsLinkRow(icon: "envelope", title: "Связаться с нами", showArrow: false,
                            url: URL(string: "mailto:berdongar@gmail.com")!)
            SettingsDivider()
            SettingsLinkRow(icon: "star", title: "Написать отзыв",
                            url: URL(string: "https://apps.apple.com/app/id000000000?action=write-review")!)
        }
    }

    private var accountSection: some View {
        SettingsSection(title: "Аккаунт") {
            SettingsRow(icon: "rectangle.portrait.and.arrow.right", title: "Выйти", destructive: true, trailing: .none) {
                Haptics.warning(); showSignOut = true
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Image("icon_preview_blue")
                .resizable()
                .scaledToFit()
                .frame(width: 64, height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            Text("reInspire")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.secondary)
            Text("Версия \(appVersion)")
                .font(.system(size: 15))
                .foregroundStyle(.tertiary)

            Link(destination: URL(string: "https://thechallenges.app/terms.html")!) {
                Label("Условия использования", systemImage: "signature")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 18)
            Link(destination: URL(string: "https://thechallenges.app/privacy.html")!) {
                Label("Политика конфиденциальности", systemImage: "checkmark.shield")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 6)
            // Apple's standard EULA -- required reference for apps with
            // auto-renewing subscriptions (App Review 3.1.2).
            Link(destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!) {
                Label("Лицензионное соглашение (EULA)", systemImage: "doc.text")
                    .font(.system(size: 14))
                    .foregroundStyle(.tertiary)
            }
            .padding(.top, 6)

            // star2 is a white shape -- invisible on the light footer on its own.
            // A soft even shadow haloes its edges so the white star reads on
            // light backgrounds while staying white (and stays fine on dark).
            Image("star2")
                .resizable()
                .scaledToFit()
                .frame(width: 200)
                .frame(maxWidth: .infinity)   // centre under the links
                .shadow(color: .black.opacity(0.22), radius: 7)
                .padding(.top, 20)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 14)
    }

    // MARK: Helpers

    private func openSystemSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - Section container

private struct SettingsSection<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 6)
            VStack(spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemBackground)))
        }
    }
}

private struct SettingsDivider: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1).padding(.leading, 58)
    }
}

// MARK: - Rows

private enum RowTrailing { case chevron, none }

private struct SettingsRow: View {
    let icon: String
    let title: String
    var value: String? = nil
    var badge: String? = nil
    var destructive: Bool = false
    var trailing: RowTrailing = .chevron
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                RowIcon(icon, destructive: destructive)
                Text(title)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(destructive ? Color.red : .primary)
                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Capsule().fill(Color.primary.opacity(0.1)))
                }
                Spacer()
                if let value {
                    Text(value).font(.system(size: 17)).foregroundStyle(.secondary)
                }
                if trailing == .chevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct SettingsMenuRow: View {
    let icon: String
    let title: String
    @Binding var selection: String
    let options: [String]
    var display: (String) -> String = { $0 }

    var body: some View {
        Menu {
            ForEach(options, id: \.self) { opt in
                Button { Haptics.selection(); selection = opt } label: {
                    if opt == selection { Label(display(opt), systemImage: "checkmark") }
                    else { Text(display(opt)) }
                }
            }
        } label: {
            HStack(spacing: 16) {
                RowIcon(icon)
                Text(title).font(.system(size: 18, weight: .medium)).foregroundStyle(.primary)
                Spacer()
                Text(display(selection)).font(.system(size: 17)).foregroundStyle(.secondary)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16).padding(.vertical, 16)
            .contentShape(Rectangle())
        }
    }
}

private struct SettingsToggleRow: View {
    let icon: String
    let title: String
    var subtitle: String? = nil
    @Binding var isOn: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                RowIcon(icon)
                Text(title).font(.system(size: 18, weight: .medium)).foregroundStyle(.primary)
                Spacer()
                Toggle("", isOn: $isOn)
                    .labelsHidden()
                    .tint(Color(hex: "30D158"))
                    .hapticFeedback(.selection, trigger: isOn)
            }
            if let subtitle {
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.leading, 58)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 16)
    }
}

private struct SettingsStatusRow: View {
    let icon: String
    let title: String
    let statusText: String
    let statusColor: Color
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 16) {
                RowIcon(icon)
                Text(title).font(.system(size: 18, weight: .medium)).foregroundStyle(.primary)
                Spacer()
                HStack(spacing: 7) {
                    Circle().fill(statusColor).frame(width: 8, height: 8)
                    Text(statusText).font(.system(size: 17, weight: .medium)).foregroundStyle(statusColor)
                }
            }
            Text(subtitle)
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.leading, 58)
        }
        .padding(.horizontal, 16).padding(.vertical, 16)
    }
}

private struct SettingsLinkRow: View {
    let icon: String
    let title: String
    var showArrow: Bool = true
    let url: URL

    var body: some View {
        Link(destination: url) {
            HStack(spacing: 16) {
                RowIcon(icon)
                Text(title).font(.system(size: 18, weight: .medium)).foregroundStyle(.primary)
                Spacer()
                if showArrow {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 16)
            .contentShape(Rectangle())
        }
    }
}

private struct SettingsShareRow: View {
    let icon: String
    let title: String
    let url: URL

    var body: some View {
        ShareLink(item: url) {
            HStack(spacing: 16) {
                RowIcon(icon)
                Text(title).font(.system(size: 18, weight: .medium)).foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 16).padding(.vertical, 16)
            .contentShape(Rectangle())
        }
    }
}

private struct RowIcon: View {
    let name: String
    var destructive: Bool = false
    init(_ name: String, destructive: Bool = false) { self.name = name; self.destructive = destructive }
    var body: some View {
        Image(systemName: name)
            .font(.system(size: 20, weight: .regular))
            .foregroundStyle(destructive ? Color.red : .secondary)
            .frame(width: 26, alignment: .center)
    }
}

#Preview {
    SettingsView()
}
