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
                        .font(.manrope(.semiBold, size: 17))
                        .lineLimit(1)
                    Text(activity.type.displayName)
                        .font(.manrope(.medium, size: 12))
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

            if activity.effectiveCompletionMode.needsTarget, let target = activity.goalTarget {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: activity.goalProgress, total: target)
                        .tint(Color(hex: "0048E2"))
                    let unit = activity.effectiveCompletionUnit
                    let suffix = unit.isEmpty ? "" : " \(unit)"
                    Text(String(format: "%.0f / %.0f", activity.goalProgress, target) + suffix)
                        .font(.manrope(.medium, size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            if let deadline = activity.deadline {
                HStack {
                    Image(systemName: "calendar")
                        .font(.caption2)
                    Text(deadline, style: .date)
                        .font(.manrope(.medium, size: 11))
                }
                .foregroundStyle(deadlineColor(deadline))
            }

            if activity.isFromParent {
                Label("От родителя", systemImage: "person.2.fill")
                    .font(.manrope(.medium, size: 11))
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
            .font(.manrope(.semiBold, size: 11))
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
