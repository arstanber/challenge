import SwiftUI

struct ActivityRowView: View {
    let activity: Activity

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: activity.type.icon)
                    .font(.body)
                    .foregroundStyle(typeColor)
                    .frame(width: 28, height: 28)
                    .background(typeColor.opacity(0.15), in: Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(activity.title)
                        .font(.headline)
                        .lineLimit(1)
                    Text(activity.type.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    StatusBadge(status: activity.status)
                    if activity.type.hasStreak && activity.streakCurrent > 0 {
                        StreakBadgeView(streak: activity.streakCurrent, size: 12)
                    }
                }
            }

            if activity.type == .goal, let target = activity.goalTarget {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: activity.goalProgress, total: target)
                        .tint(Color(hex: "0048E2"))
                    Text(String(format: "%.0f / %.0f", activity.goalProgress, target))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let deadline = activity.deadline {
                HStack {
                    Image(systemName: "calendar")
                        .font(.caption2)
                    Text(deadline, style: .date)
                        .font(.caption2)
                }
                .foregroundStyle(deadlineColor(deadline))
            }

            if activity.isFromParent {
                Label("From parent", systemImage: "person.2.fill")
                    .font(.caption2)
                    .foregroundStyle(.purple)
            }
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.separator, lineWidth: 0.5)
        )
    }

    private var typeColor: Color {
        switch activity.type {
        case .challenge: return Color(hex: "0048E2")
        case .goal: return .green
        case .task: return .orange
        case .habit: return .purple
        case .assignment: return .pink
        }
    }

    private func deadlineColor(_ date: Date) -> Color {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days < 0 { return .red }
        if days <= 1 { return .orange }
        return .secondary
    }
}

struct StatusBadge: View {
    let status: ActivityStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }

    private var color: Color {
        switch status {
        case .active: return Color(hex: "0048E2")
        case .completed: return .green
        case .failed: return .red
        }
    }
}

#Preview {
    ActivityRowView(activity: Activity(
        id: UUID(),
        userId: UUID(),
        assignedBy: nil,
        title: "Morning workout",
        description: "Go to gym",
        type: .challenge,
        condition: "Photo at gym",
        frequency: .daily,
        deadline: Calendar.current.date(byAdding: .day, value: 3, to: Date()),
        reminderTime: nil,
        status: .active,
        streakCurrent: 7,
        streakBest: 14,
        goalProgress: 0,
        goalTarget: nil,
        createdAt: Date()
    ))
    .padding()
}
