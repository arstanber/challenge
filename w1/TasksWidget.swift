import WidgetKit
import SwiftUI

struct TasksWidget: Widget {
    let kind = "TasksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TasksWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { Color(.systemBackground) }
        }
        .configurationDisplayName("Today's Activities")
        .description("Your active activities and what's left today.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct TasksWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    private var maxRows: Int { family == .systemLarge ? 6 : 3 }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            if snapshot.tasks.isEmpty {
                emptyState
            } else {
                VStack(spacing: 8) {
                    ForEach(snapshot.tasks.prefix(maxRows)) { task in
                        TaskRow(task: task)
                    }
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Text("Today")
                .font(.system(.headline, design: .rounded).weight(.bold))
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                Text("\(snapshot.streakCurrent)")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(.orange)
            }
            Text("·")
                .foregroundStyle(.secondary)
            Text("\(snapshot.todayDone)/\(snapshot.dailyGoal)")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(snapshot.goalReached ? .green : .secondary)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "checkmark.seal.fill")
                .font(.title)
                .foregroundStyle(.green)
            Text("All clear!")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
            Text("No active activities")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.top, 8)
    }
}

private struct TaskRow: View {
    let task: WidgetTask

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: task.isDone ? "checkmark.circle.fill" : task.typeIcon)
                .font(.system(size: 15))
                .foregroundStyle(task.isDone ? .green : task.color)
                .frame(width: 22)

            Text(task.title)
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .lineLimit(1)
                .strikethrough(task.isDone, color: .secondary)
                .foregroundStyle(task.isDone ? .secondary : .primary)

            Spacer(minLength: 4)

            if let deadline = task.deadline, !task.isDone {
                Text(deadline, style: .date)
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(deadlineColor(deadline))
            }
        }
    }

    private func deadlineColor(_ date: Date) -> Color {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days < 0 { return .red }
        if days <= 1 { return .orange }
        return .secondary
    }
}

#Preview(as: .systemMedium) {
    TasksWidget()
} timeline: {
    ChallengeEntry(date: .now, snapshot: .placeholder)
}

#Preview(as: .systemLarge) {
    TasksWidget()
} timeline: {
    ChallengeEntry(date: .now, snapshot: .placeholder)
}
