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
    @AppStorage(AppPrefs.Key.liveActivityEnabled) private var liveActivityEnabled = true
    // Habits
    // Default true: done tasks collect at the bottom (HomeView reads this too).
    @AppStorage("groupCompleted") private var groupCompleted = true
    @AppStorage("strictMode") private var strictMode = true
    @AppStorage("requirePhotoVerification") private var requirePhoto = true

    @State private var showPremium = false
    @State private var showAppIcon = false
    @State private var showHallOfFame = false
    @State private var showSignOut = false
    @State private var showDeleteAccount = false
    @State private var isDeletingAccount = false
    @State private var isExporting = false
    @State private var exportFile: ExportFile?
    @State private var exportFailed = false
    @State private var showChangePassword = false
    @State private var showTelegramLink = false
    @State private var showConnectors = false
    @State private var showDuels = false
    @State private var showLeaderboard = false
    @State private var showReferral = false
    @State private var showFamily = false
    @State private var showStatistics = false
    @State private var showLocations = false
    @State private var showProfile = false

    private let blue = Color(hex: "0A84FF")

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()

            // Brand star as a full-width watermark anchored to the bottom edge,
            // shown in full behind the scrolling content.
            VStack {
                Spacer()
                Image("star2")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
            }
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 26) {
                    profileCard
                    // Upsell only makes sense for free users; isPremium also
                    // covers temporary referral PRO (pro_until).
                    if auth.currentUser?.isPremium != true {
                        premiumCard
                    }
                    subscriptionSection
                    personalSection
                    globalSection
                    habitsSection
                    syncSection
                    connectionsSection
                    infoSection
                    privacySection
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
        .sheet(isPresented: $showLocations) {
            LocationsSettingsView()
        }
        .sheet(isPresented: $showProfile) {
            ProfileEditView().environment(auth)
        }
        .sheet(isPresented: $showChangePassword) {
            ChangePasswordSheet()
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
        .onChange(of: liveActivityEnabled) { _, enabled in
            // Off -> dismiss right away. On -> a fresh activity re-launches on
            // the next snapshot rebuild from ActivitiesViewModel.
            if !enabled { LiveActivityService.shared.endCurrent() }
        }
        .confirmationDialog("Выйти из аккаунта?", isPresented: $showSignOut, titleVisibility: .visible) {
            Button("Выйти", role: .destructive) {
                Haptics.warning(); dismiss(); AuthService.shared.signOut()
            }
            Button("Отмена", role: .cancel) {}
        }
        .confirmationDialog(
            "Удалить аккаунт?",
            isPresented: $showDeleteAccount,
            titleVisibility: .visible
        ) {
            Button("Удалить навсегда", role: .destructive) { deleteAccount() }
            Button("Отмена", role: .cancel) {}
        } message: {
            Text("Все ваши привычки, отчёты и профиль будут удалены без возможности восстановления.")
        }
        .sheet(item: $exportFile) { file in
            ShareSheet(items: [file.url])
        }
        .alert("Не удалось выгрузить данные", isPresented: $exportFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Попробуйте ещё раз позже.")
        }
    }

    private func deleteAccount() {
        guard !isDeletingAccount else { return }
        isDeletingAccount = true
        Task {
            let ok = await PrivacyService.shared.deleteAccount()
            isDeletingAccount = false
            if ok { dismiss() }  // signOut already cleared the session -> RootView returns to onboarding
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

    // MARK: Profile card

    private var profileCard: some View {
        Button { Haptics.tap(); showProfile = true } label: {
            HStack(spacing: 14) {
                UserAvatarView(
                    urlString: auth.currentUser?.avatarURL,
                    label: auth.currentUser?.displayLabel ?? "?",
                    size: 56
                )
                VStack(alignment: .leading, spacing: 3) {
                    Text(auth.currentUser?.displayLabel ?? "Профиль")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text("Имя, фото и аккаунт")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color(.secondarySystemBackground)))
        }
        .buttonStyle(.plain)
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

    // Always visible -- the premium upsell card above is hidden once the user
    // has PRO (incl. the welcome trial), but subscribers still need a way to
    // open the plans / restore purchases. Title reflects current entitlement.
    private var subscriptionSection: some View {
        SettingsSection(title: "Подписка") {
            SettingsRow(
                icon: "crown",
                title: auth.currentUser?.isPremium == true ? "Управление подпиской" : "Оформить подписку",
                trailing: .chevron
            ) {
                Haptics.tap(); showPremium = true
            }
        }
    }

    private var personalSection: some View {
        SettingsSection(title: "Личное") {
            SettingsRow(icon: "trophy", title: "Зал славы", trailing: .chevron) {
                Haptics.tap(); showHallOfFame = true
            }
            SettingsDivider()
            // TEMP: Статистика hidden -- restore this row + divider to bring it back.
            // SettingsRow(icon: "chart.xyaxis.line", title: "Статистика", trailing: .chevron) {
            //     Haptics.tap(); showStatistics = true
            // }
            // SettingsDivider()
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
            SettingsDivider()
            SettingsToggleRow(
                icon: "capsule.portrait",
                title: "Живая активность",
                subtitle: "Прогресс дня и стрик в Dynamic Island и на экране блокировки. Выключите, чтобы убрать.",
                isOn: $liveActivityEnabled
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
            SettingsRow(icon: "mappin.and.ellipse", title: "Локации", trailing: .chevron) {
                Haptics.tap(); showLocations = true
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

    private var privacySection: some View {
        SettingsSection(title: "Конфиденциальность и данные") {
            SettingsLinkRow(icon: "checkmark.shield", title: "Политика конфиденциальности",
                            url: URL(string: "https://thechallenges.app/privacy.html")!)
            SettingsDivider()
            SettingsRow(icon: "square.and.arrow.down",
                        title: "Экспорт моих данных",
                        trailing: isExporting ? .none : .chevron) {
                Haptics.tap(); exportData()
            }
            SettingsDivider()
            SettingsRow(icon: "trash", title: "Удалить аккаунт", destructive: true, trailing: .none) {
                Haptics.warning(); showDeleteAccount = true
            }
        }
        .overlay(alignment: .center) {
            if isExporting || isDeletingAccount {
                ProgressView().padding(.top, 40)
            }
        }
    }

    private var accountSection: some View {
        SettingsSection(title: "Аккаунт") {
            SettingsRow(icon: "key", title: "Сменить пароль", trailing: .chevron) {
                Haptics.tap(); showChangePassword = true
            }
            SettingsDivider()
            SettingsRow(icon: "rectangle.portrait.and.arrow.right", title: "Выйти", destructive: true, trailing: .none) {
                Haptics.warning(); showSignOut = true
            }
        }
    }

    private func exportData() {
        guard !isExporting else { return }
        isExporting = true
        Task {
            defer { isExporting = false }
            do {
                exportFile = ExportFile(url: try await PrivacyService.shared.exportData())
            } catch {
                exportFailed = true
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

// MARK: - Data export

/// Wraps the export file URL so it can drive a `.sheet(item:)`.
private struct ExportFile: Identifiable {
    let url: URL
    var id: String { url.path }
}

/// Minimal share-sheet bridge for handing a generated file to the system.
private struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Change password

private struct ChangePasswordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var password = ""
    @State private var confirm = ""
    @State private var saving = false
    @State private var errorMessage: String?
    @State private var saved = false

    private var isValid: Bool { password.count >= 6 && password == confirm }

    var body: some View {
        NavigationStack {
            Form {
                Section("Новый пароль (от 6 символов)") {
                    SecureField("Новый пароль", text: $password)
                    SecureField("Повтори пароль", text: $confirm)
                }
                if let errorMessage {
                    Section { Text(errorMessage).font(.caption).foregroundStyle(.red) }
                }
                if saved {
                    Section { Label("Пароль изменён", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                }
            }
            .navigationTitle("Сменить пароль")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(!isValid || saving)
                        .overlay { if saving { ProgressView().scaleEffect(0.7) } }
                }
            }
        }
    }

    private func save() async {
        saving = true
        errorMessage = nil
        defer { saving = false }
        do {
            try await AuthService.shared.changePassword(to: password)
            Haptics.success(); saved = true
            try? await Task.sleep(nanoseconds: 700_000_000)
            dismiss()
        } catch {
            errorMessage = "Не удалось изменить пароль. Попробуй ещё раз."
        }
    }
}

#Preview {
    SettingsView()
}
