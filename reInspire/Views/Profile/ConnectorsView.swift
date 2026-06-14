import SwiftUI

/// Full "Connectors" screen: free data sources everyone can use, plus a Max-only
/// section (Strava, Whoop, Notion, Google Docs/Drive, Gmail) gated behind a paywall.
struct ConnectorsView: View {
    @State private var service = ConnectorService.shared
    @State private var auth = AuthService.shared
    @State private var showTelegramLink = false
    @State private var showPremium = false
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
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(connector.tint.opacity(0.15))
                    .frame(width: 40, height: 40)
                    .overlay {
                        Image(systemName: connector.icon)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(connector.tint)
                    }

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

#Preview {
    NavigationStack { ConnectorsView() }
}
