import SwiftUI

/// Bottom sheet shown right after a task is created, offering topic-matched
/// data connectors so progress can be tracked automatically.
struct ConnectorSuggestionSheet: View {
    let suggestion: ConnectorSuggestionEngine.Suggestion

    @Environment(\.dismiss) private var dismiss
    @State private var service = ConnectorService.shared
    @State private var auth = AuthService.shared
    @State private var connecting: DataConnector?
    @State private var showPremium = false
    @State private var errorMessage: String?

    private var plan: UserPlan { auth.currentUser?.plan ?? .free }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header

            VStack(spacing: 0) {
                ForEach(Array(suggestion.connectors.enumerated()), id: \.element) { index, connector in
                    if index > 0 {
                        Rectangle()
                            .fill(Color.primary.opacity(0.08))
                            .frame(height: 1)
                            .padding(.leading, 70)
                    }
                    row(for: connector)
                }
            }
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )

            Button {
                Haptics.tap()
                dismiss()
            } label: {
                Text("Не сейчас")
                    .font(.system(size: 16, weight: .medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.top, 26)
        .readableWidth(560)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
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

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(hex: "7C4DF0"))
                Text("Отслеживать автоматически?")
                    .font(.system(size: 22, weight: .bold))
            }
            Text(subtitle)
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var subtitle: String {
        let shown = suggestion.taskTitles.prefix(2).map { "«\($0)»" }.joined(separator: ", ")
        let tail = suggestion.taskTitles.count > 2 ? String(localized: " и ещё \(suggestion.taskTitles.count - 2)") : ""
        let noun = suggestion.taskTitles.count > 1 ? String(localized: "заданиям") : String(localized: "заданию")
        return String(localized: "Подключи источник данных, и прогресс по \(noun) \(shown)\(tail) будет засчитываться сам -- без ручных отчётов.")
    }

    // MARK: - Row

    @ViewBuilder
    private func row(for connector: DataConnector) -> some View {
        let unlocked = connector.isUnlocked(for: plan)
        let connected = service.isConnected(connector)

        Button {
            tap(connector, unlocked: unlocked, connected: connected)
        } label: {
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

                trailing(for: connector, unlocked: unlocked, connected: connected)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func trailing(for connector: DataConnector, unlocked: Bool, connected: Bool) -> some View {
        if connecting == connector {
            ProgressView()
        } else if connected {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color(hex: "30D158"))
        } else if !unlocked {
            HStack(spacing: 5) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("MAX")
                    .font(.caption2.bold())
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                LinearGradient(
                    colors: [Color(hex: "7C4DF0"), Color(hex: "5B2FD6")],
                    startPoint: .leading,
                    endPoint: .trailing
                ),
                in: Capsule()
            )
        } else {
            Text("Подключить")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Color(hex: "7C4DF0"), in: Capsule())
        }
    }

    // MARK: - Actions

    private func tap(_ connector: DataConnector, unlocked: Bool, connected: Bool) {
        Haptics.tap()
        guard !connected, connecting == nil else { return }
        guard unlocked else {
            showPremium = true
            return
        }
        connecting = connector
        Task {
            do {
                try await service.connect(connector)
                ConnectorSuggestionEngine.shared.markConnected(connector)
                Haptics.success()
            } catch ConnectorError.requiresMax {
                showPremium = true
            } catch ConnectorError.oauthCancelled {
                // user-initiated, no error banner
            } catch {
                errorMessage = error.localizedDescription
            }
            connecting = nil
        }
    }
}
