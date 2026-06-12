import SwiftUI
import Supabase

// MARK: - Leaderboard (#1)
// Shows weekly streak-based rankings among family/friends.
// Backend: Supabase RPC `get_leaderboard(user_id)` — see migration file.

struct LeaderboardEntry: Decodable, Identifiable {
    let rank: Int
    let userId: UUID
    let email: String
    let streakCurrent: Int
    let streakBest: Int
    let totalCompleted: Int

    var id: UUID { userId }

    enum CodingKeys: String, CodingKey {
        case rank
        case userId = "user_id"
        case email
        case streakCurrent = "streak_current"
        case streakBest = "streak_best"
        case totalCompleted = "total_completed"
    }
}

@Observable
final class LeaderboardViewModel {
    var entries: [LeaderboardEntry] = []
    var isLoading = false
    var errorMessage: String?

    func load() async {
        guard let userId = AuthService.shared.currentUser?.id else { return }
        isLoading = true
        errorMessage = nil
        do {
            let result: [LeaderboardEntry] = try await supabase
                .rpc("get_leaderboard", params: ["p_user_id": userId.uuidString])
                .execute()
                .value
            entries = result
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct LeaderboardView: View {
    @State private var vm = LeaderboardViewModel()
    @Environment(AuthService.self) private var authService

    private let blue = Color(hex: "4580FF")

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            VStack(spacing: 0) {
                // Header
                HStack {
                    Text("Рейтинг")
                        .font(.manrope(.extraBold, size: 24))
                    Spacer()
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.yellow)
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 16)

                if vm.isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else if vm.entries.isEmpty {
                    emptyState
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 10) {
                            // Top 3 podium
                            if vm.entries.count >= 3 {
                                PodiumRow(entries: Array(vm.entries.prefix(3)))
                                    .padding(.bottom, 8)
                                    .appearEffect(delay: 0.05)
                            }
                            // Full list
                            ForEach(Array(vm.entries.enumerated()), id: \.element.id) { index, entry in
                                LeaderboardRow(
                                    entry: entry,
                                    isMe: entry.userId == authService.currentUser?.id
                                )
                                .appearEffect(delay: 0.12 + Double(index) * 0.06)
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.bottom, 40)
                        .readableWidth()
                    }
                }
            }
        }
        .task { await vm.load() }
        .refreshable { await vm.load() }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("🏆")
                .font(.system(size: 56))
            Text("Пока не с кем соревноваться")
                .font(.manrope(.bold, size: 18))
            Text("Присоединись к семье, чтобы увидеть свой рейтинг")
                .font(.manrope(.medium, size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 40)
    }
}

// MARK: - Podium

private struct PodiumRow: View {
    let entries: [LeaderboardEntry]

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            // 2nd
            if entries.count > 1 {
                PodiumPillar(entry: entries[1], height: 80)
            }
            // 1st
            PodiumPillar(entry: entries[0], height: 110)
            // 3rd
            if entries.count > 2 {
                PodiumPillar(entry: entries[2], height: 60)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(RoundedRectangle(cornerRadius: 20).fill(Color(hex: "FFB200").opacity(0.08)))
    }
}

private struct PodiumPillar: View {
    let entry: LeaderboardEntry
    let height: CGFloat

    private var medal: String {
        switch entry.rank { case 1: return "🥇"; case 2: return "🥈"; default: return "🥉" }
    }

    var body: some View {
        VStack(spacing: 6) {
            Text(medal).font(.system(size: 28))
            Text(entry.email.components(separatedBy: "@").first ?? entry.email)
                .font(.manrope(.bold, size: 12))
                .lineLimit(1)
                .frame(maxWidth: 80)
            HStack(spacing: 3) {
                Image(systemName: "flame.fill").font(.caption2).foregroundStyle(.orange)
                Text("\(entry.streakCurrent)").font(.manrope(.bold, size: 13))
            }
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: "FFB200").opacity(0.3))
                .frame(width: 60, height: height)
                .overlay(alignment: .top) {
                    Text("#\(entry.rank)").font(.manrope(.bold, size: 14)).padding(.top, 8)
                }
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Row

private struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    let isMe: Bool

    var body: some View {
        HStack(spacing: 14) {
            // Rank badge
            Text("#\(entry.rank)")
                .font(.manrope(.bold, size: 15))
                .foregroundStyle(rankColor)
                .frame(width: 36)

            // Avatar
            Circle()
                .fill(isMe ? Color(hex: "4580FF").gradient : Color.black.opacity(0.08).gradient)
                .frame(width: 38, height: 38)
                .overlay {
                    Text(String(entry.email.prefix(1)).uppercased())
                        .font(.manrope(.bold, size: 16))
                        .foregroundStyle(isMe ? .white : .black.opacity(0.6))
                }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.email.components(separatedBy: "@").first ?? entry.email)
                        .font(.manrope(.bold, size: 15))
                    if isMe {
                        Text("Ты")
                            .font(.manrope(.bold, size: 11))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Capsule().fill(Color(hex: "4580FF")))
                    }
                }
                Text("Выполнено: \(entry.totalCompleted)")
                    .font(.manrope(.medium, size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Streak
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill").font(.subheadline).foregroundStyle(.orange)
                    Text("\(entry.streakCurrent)").font(.manrope(.extraBold, size: 18))
                }
                Text("рекорд \(entry.streakBest)")
                    .font(.manrope(.medium, size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isMe ? Color(hex: "4580FF").opacity(0.07) : Color.black.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(isMe ? Color(hex: "4580FF").opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    private var rankColor: Color {
        switch entry.rank {
        case 1: return Color(hex: "FFB200")
        case 2: return Color(hex: "8E8E93")
        case 3: return Color(hex: "CD7F32")
        default: return .secondary
        }
    }
}
