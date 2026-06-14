import SwiftUI

// MARK: - Referral program

/// "Приглашай друзей -- получай PRO": share code, claim rewards
/// (3 days PRO or a streak freeze per friend), milestone progress to the
/// 10-friends month of PRO, and a redeem field for invited users.
struct ReferralView: View {
    @Environment(AuthService.self) private var authService
    @State private var service = ReferralService.shared

    @State private var redeemCode = ""
    @State private var showRedeemSuccess = false

    private var nextMilestoneProgress: Int {
        (service.info?.total ?? 0) % 10
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                heroCard
                if let info = service.info, !info.unclaimed.isEmpty {
                    rewardsSection(info)
                }
                milestoneCard
                if authService.currentUser?.referredBy == nil {
                    redeemSection
                }
                if let until = authService.currentUser?.proUntil, until > Date() {
                    proStatusLine(until: until)
                }
            }
            .padding(18)
            .readableWidth()
        }
        .navigationTitle("Пригласить друга")
        .navigationBarTitleDisplayMode(.inline)
        .task { await service.load() }
        .refreshable { await service.load() }
        .alert("Код принят! 🎉", isPresented: $showRedeemSuccess) {
            Button("Отлично") {}
        } message: {
            Text("Тебе начислено 3 дня PRO. Другу тоже прилетит награда.")
        }
        .alert("Ошибка", isPresented: Binding(
            get: { service.errorMessage != nil },
            set: { if !$0 { service.errorMessage = nil } }
        )) {
            Button("OK") { service.errorMessage = nil }
        } message: {
            Text(service.errorMessage ?? "")
        }
    }

    // MARK: Hero

    private var heroCard: some View {
        VStack(spacing: 14) {
            Text("🎁")
                .font(.system(size: 44))
            Text("Приглашай друзей -- получай PRO")
                .font(.system(size: 20, weight: .bold))
                .multilineTextAlignment(.center)
            Text("За каждого друга: 3 дня PRO или 1 заморозка серии. 10 друзей -- целый месяц PRO.")
                .font(.system(size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            if let code = service.info?.code {
                Text(code)
                    .font(.system(size: 34, weight: .heavy, design: .monospaced))
                    .tracking(6)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 10)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 14))
                    .onTapGesture {
                        UIPasteboard.general.string = code
                        Haptics.success()
                    }

                ShareLink(item: shareText(code: code)) {
                    Label("Поделиться кодом", systemImage: "paperplane.fill")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "0048E2"))
            } else if service.isLoading {
                ProgressView().padding(.vertical, 16)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private func shareText(code: String) -> String {
        "Я закрываю цели в reInspire -- AI проверяет фото, не отвертишься 😄 Заходи по моему коду \(code), получишь 3 дня PRO: https://thechallenges.app"
    }

    // MARK: Unclaimed rewards

    private func rewardsSection(_ info: ReferralService.Info) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Награды: \(info.unclaimed.count)")
                .font(.headline)
            ForEach(info.unclaimed) { referral in
                HStack(spacing: 10) {
                    Text("🎉")
                        .font(.system(size: 24))
                    Text("Друг присоединился")
                        .font(.system(size: 14, weight: .medium))
                    Spacer()
                    Button("3 дня PRO") {
                        Haptics.success()
                        Task { await service.claim(referral.id, reward: .pro3d) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color(hex: "0048E2"))
                    .controlSize(.small)

                    Button("Заморозка") {
                        Haptics.success()
                        Task { await service.claim(referral.id, reward: .freeze) }
                    }
                    .buttonStyle(.bordered)
                    .tint(.cyan)
                    .controlSize(.small)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: Milestone

    private var milestoneCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("До месяца PRO")
                    .font(.headline)
                Spacer()
                Text("\(nextMilestoneProgress) / 10")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(Color(hex: "0048E2"))
            }
            ProgressView(value: Double(nextMilestoneProgress), total: 10)
                .tint(Color(hex: "0048E2"))
            Text("Каждый десятый друг приносит 30 дней PRO автоматически.")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let total = service.info?.total, total > 0 {
                Text("Всего приглашено: \(total)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: Redeem

    private var redeemSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Тебя пригласили?")
                .font(.headline)
            Text("Введи код друга и получи 3 дня PRO.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 10) {
                TextField("Код", text: $redeemCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .monospaced))
                    .padding(12)
                    .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: 12))
                Button("Применить") {
                    Haptics.tap()
                    let code = redeemCode
                    Task {
                        if await service.redeem(code: code) {
                            redeemCode = ""
                            showRedeemSuccess = true
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "0048E2"))
                .disabled(redeemCode.trimmingCharacters(in: .whitespaces).count < 4)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    // MARK: PRO status

    private func proStatusLine(until: Date) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill")
                .foregroundStyle(.orange)
            Text("PRO активен до \(until.formatted(date: .long, time: .omitted))")
                .font(.system(size: 14, weight: .medium))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }
}
