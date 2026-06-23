import SwiftUI

/// Full "Connectors" screen: free data sources everyone can use, plus a Max-only
/// section (Strava) gated behind a paywall.
struct ConnectorsView: View {
    @State private var service = ConnectorService.shared
    @State private var auth = AuthService.shared
    @State private var showTelegramLink = false
    @State private var showPremium = false
    @State private var showClockSettings = false
    @State private var showChessSettings = false
    @State private var healthSheet: DataConnector?
    @State private var errorMessage: String?

    private var plan: UserPlan { auth.currentUser?.plan ?? .free }

    private var freeConnectors: [DataConnector] {
        DataConnector.allCases.filter { $0.requiredPlan == .free && $0.isConfigured }
    }

    private var maxConnectors: [DataConnector] {
        DataConnector.allCases.filter { $0.requiredPlan == .max && $0.isConfigured }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 26) {
                freeSection
                maxSection
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 50)
            .readableWidth()
        }
        .background(Color(.systemBackground))
        .navigationTitle("Коннекторы")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showTelegramLink) {
            NavigationStack { TelegramLinkView() }
        }
        .sheet(isPresented: $showPremium) {
            NavigationStack { PremiumView() }
        }
        .sheet(isPresented: $showClockSettings) {
            ClockReminderSheet(service: service)
        }
        .sheet(isPresented: $showChessSettings) {
            ChessUsernameSheet(service: service)
        }
        .sheet(item: $healthSheet) { connector in
            HealthConnectSheet(connector: connector, service: service)
        }
        .alert("Ошибка", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("ОК") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: - Sections

    private var freeSection: some View {
        ConnectorSection(title: "Бесплатные") {
            ForEach(Array(freeConnectors.enumerated()), id: \.element) { index, connector in
                if index > 0 { ConnectorDivider() }
                row(for: connector)
            }
        }
    }

    private var maxSection: some View {
        ConnectorSection(title: "Max", badge: true) {
            ForEach(Array(maxConnectors.enumerated()), id: \.element) { index, connector in
                if index > 0 { ConnectorDivider() }
                row(for: connector)
            }
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func row(for connector: DataConnector) -> some View {
        let unlocked = connector.isUnlocked(for: plan)
        let connected = service.isConnected(connector)

        ConnectorRow(
            connector: connector,
            connected: connected,
            locked: !unlocked
        ) {
            handleTap(connector, unlocked: unlocked, connected: connected)
        }
    }

    // MARK: - Actions

    private func handleTap(_ connector: DataConnector, unlocked: Bool, connected: Bool) {
        Haptics.tap()

        guard unlocked else {
            showPremium = true
            return
        }

        if connector == .telegram {
            showTelegramLink = true
            return
        }

        // The alarm opens a settings sheet (enable + pick the time) instead of
        // a one-shot connect toggle.
        if connector == .appleClock {
            showClockSettings = true
            return
        }

        // Chess.com connects by username (public API, no OAuth).
        if connector == .chessCom {
            showChessSettings = true
            return
        }

        // Apple Health / Fitness open an explainer that clearly identifies the
        // HealthKit data we read (and that we never write) before the system
        // permission sheet -- required for App Store guideline 2.5.1.
        if connector.kind == .health {
            healthSheet = connector
            return
        }

        Task {
            do {
                if connected {
                    await service.disconnect(connector)
                } else {
                    try await service.connect(connector)
                }
            } catch ConnectorError.requiresMax {
                showPremium = true
            } catch ConnectorError.oauthCancelled {
                // user-initiated, no error banner
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Section container

private struct ConnectorSection<Content: View>: View {
    let title: String
    var badge: Bool = false
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.secondary)
                if badge {
                    Text("MAX")
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(
                            LinearGradient(
                                colors: [Color(hex: "7C4DF0"), Color(hex: "5B2FD6")],
                                startPoint: .leading,
                                endPoint: .trailing
                            ),
                            in: Capsule()
                        )
                        .foregroundStyle(.white)
                }
            }
            .padding(.leading, 6)
            VStack(spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemBackground)))
        }
    }
}

private struct ConnectorDivider: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1).padding(.leading, 70)
    }
}

// MARK: - Row

private struct ConnectorRow: View {
    let connector: DataConnector
    let connected: Bool
    let locked: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                ConnectorGlyph(connector: connector, size: 40, cornerRadius: 12)

                VStack(alignment: .leading, spacing: 3) {
                    Text(connector.displayName)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(connector.summary)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                trailing
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var trailing: some View {
        if locked {
            Image(systemName: "lock.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.tertiary)
        } else if connected {
            HStack(spacing: 6) {
                Text("Подключено")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color(hex: "30D158"))
            }
        } else {
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.tertiary)
        }
    }
}

// MARK: - Clock reminder settings

private struct ClockReminderSheet: View {
    let service: ConnectorService
    @Environment(\.dismiss) private var dismiss

    @State private var enabled = false
    @State private var time = Date()
    @State private var saving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Ежедневное напоминание", isOn: $enabled)
                    if enabled {
                        DatePicker("Время", selection: $time, displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text("В выбранное время придёт уведомление со списком задач на день. iOS не даёт ставить системный будильник из приложения, поэтому это локальное напоминание.")
                }
                if let errorMessage {
                    Section { Text(errorMessage).font(.caption).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Будильник")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Готово") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(saving)
                }
            }
            .onAppear {
                enabled = service.isConnected(.appleClock)
                time = service.clockReminderTime
            }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            if enabled {
                try await service.enableClock(at: time)
            } else {
                service.disableClock()
            }
            Haptics.success()
            dismiss()
        } catch ConnectorError.authorizationDenied {
            errorMessage = String(localized: "Разреши уведомления в настройках, чтобы получать напоминание.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - Apple Health / Fitness explainer

/// Clearly identifies the HealthKit integration before the system permission
/// sheet: what data reInspire reads, and that it never writes to Apple Health.
/// Satisfies App Store guideline 2.5.1 ("clearly identify HealthKit functionality
/// in the app's user interface").
private struct HealthConnectSheet: View {
    let connector: DataConnector
    let service: ConnectorService
    @Environment(\.dismiss) private var dismiss

    @State private var working = false
    @State private var errorMessage: String?

    private var isConnected: Bool { service.isConnected(connector) }

    /// The exact HealthKit data types reInspire reads (mirrors HealthKitConnector).
    private let dataTypes: [(icon: String, label: String)] = [
        ("figure.walk",          String(localized: "Шаги")),
        ("flame.fill",           String(localized: "Активная энергия (калории)")),
        ("timer",                String(localized: "Минуты тренировок")),
        ("ruler",                String(localized: "Дистанция ходьбы и бега"))
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header

                    Text("reInspire читает указанные ниже данные из приложения «Здоровье» (Apple Health через HealthKit), чтобы автоматически засчитывать выполнение целей -- например, шаги или тренировки. Подключение не обязательно: цели всегда можно подтвердить фото.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Что reInspire читает из Здоровья")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(dataTypes, id: \.label) { item in
                            HStack(spacing: 12) {
                                Image(systemName: item.icon)
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(Color(hex: "FF2D55"))
                                    .frame(width: 24)
                                Text(item.label)
                                    .font(.system(size: 16))
                                    .foregroundStyle(.primary)
                            }
                        }
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground)))

                    Label("reInspire не записывает никакие данные в Здоровье -- доступ только на чтение.", systemImage: "lock.shield.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let errorMessage {
                        Text(errorMessage).font(.caption).foregroundStyle(.red)
                    }
                }
                .padding(20)
            }
            .safeAreaInset(edge: .bottom) { bottomBar }
            .navigationTitle(connector.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Закрыть") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            ConnectorGlyph(connector: connector, size: 52, cornerRadius: 14)
            VStack(alignment: .leading, spacing: 3) {
                Text(connector.displayName)
                    .font(.system(size: 20, weight: .semibold))
                Text(connector.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        if isConnected {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Color(hex: "30D158"))
                    Text("Подключено").font(.system(size: 15, weight: .medium))
                }
                Button(role: .destructive) {
                    Task { await service.disconnect(connector); Haptics.tap(); dismiss() }
                } label: {
                    Text("Отключить").font(.system(size: 15, weight: .medium))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(16)
            .background(.bar)
        } else {
            Button(action: connect) {
                Group {
                    if working { ProgressView().tint(.white) }
                    else { Text("Подключить Здоровье").font(.system(size: 17, weight: .semibold)) }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity).frame(height: 50)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color(hex: "FF2D55")))
            }
            .disabled(working)
            .padding(16)
            .background(.bar)
        }
    }

    private func connect() {
        working = true
        Task {
            defer { working = false }
            do {
                try await service.connect(connector)
                Haptics.success()
                dismiss()
            } catch ConnectorError.unavailable {
                errorMessage = String(localized: "Здоровье недоступно на этом устройстве.")
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// MARK: - Chess.com username settings

private struct ChessUsernameSheet: View {
    let service: ConnectorService
    @Environment(\.dismiss) private var dismiss

    @State private var username = ""
    @State private var saving = false
    @State private var errorMessage: String?

    private var isConnected: Bool { service.isConnected(.chessCom) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Имя пользователя Chess.com", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } footer: {
                    Text("Введи свой ник на Chess.com. Мы будем считать сыгранные за день партии через публичный API -- авторизация не нужна.")
                }
                if let errorMessage {
                    Section { Text(errorMessage).font(.caption).foregroundStyle(.red) }
                }
                if isConnected {
                    Section {
                        Button(role: .destructive) {
                            service.disconnectChess(); Haptics.tap(); dismiss()
                        } label: {
                            Text("Отключить")
                        }
                    }
                }
            }
            .navigationTitle("Chess.com")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Отмена") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Подключить") { Task { await save() } }
                        .fontWeight(.semibold)
                        .disabled(saving || username.trimmingCharacters(in: .whitespaces).isEmpty)
                        .overlay { if saving { ProgressView().scaleEffect(0.7) } }
                }
            }
            .onAppear { username = service.chessUsername ?? "" }
        }
    }

    private func save() async {
        saving = true
        defer { saving = false }
        do {
            try await service.connectChess(username: username)
            Haptics.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    NavigationStack { ConnectorsView() }
}
