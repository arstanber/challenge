import SwiftUI

struct StreakBadgeView: View {
    let streak: Int
    var size: CGFloat = 14

    var body: some View {
        if streak > 0 {
            HStack(spacing: 2) {
                Image(systemName: "flame.fill")
                    .font(.system(size: size))
                    .foregroundStyle(.orange)
                Text("\(streak)")
                    .font(.system(size: size, weight: .bold))
                    .foregroundStyle(.orange)
            }
        }
    }
}

struct StreakMilestoneView: View {
    let streak: Int

    private var milestone: Int? {
        Constants.App.streakMilestones.last { streak >= $0 }
    }

    var body: some View {
        if let milestone {
            Label("\(milestone) day streak!", systemImage: "trophy.fill")
                .font(.caption)
                .foregroundStyle(.yellow)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.yellow.opacity(0.15), in: Capsule())
        }
    }
}

#Preview {
    VStack {
        StreakBadgeView(streak: 7)
        StreakBadgeView(streak: 30, size: 20)
        StreakMilestoneView(streak: 30)
    }
}
