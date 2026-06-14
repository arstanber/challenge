import WidgetKit
import SwiftUI
import AppIntents

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
            if snapshot.risk == .critical {
                Text("until 00:00!")
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.red, in: Capsule())
            }
            Spacer()
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .font(.caption)
                    .foregroundStyle(flameColor)
                Text("\(snapshot.streakCurrent)")
                    .font(.system(.subheadline, design: .rounded).weight(.bold))
                    .foregroundStyle(flameColor)
            }
            Text("·")
                .foregroundStyle(.secondary)
            Text("\(snapshot.todayDone)/\(snapshot.dailyGoal)")
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(progressColor)
        }
    }

    private var flameColor: Color {
        switch snapshot.risk {
        case .none:     return .orange
        case .atRisk:   return .orange
        case .critical: return .red
        }
    }

    private var progressColor: Color {
        if snapshot.goalReached { return .green }
        switch snapshot.risk {
        case .none:     return .secondary
        case .atRisk:   return .orange
        case .critical: return .red
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

    /// Non-photo tasks complete in place via AppIntent; photo tasks open the
    /// app, since the proof shot needs the camera.
    private var isCheckable: Bool { !task.isDone && task.requiresPhoto != true }

    var body: some View {
        HStack(spacing: 10) {
            if isCheckable {
                Button(intent: CompleteTaskIntent(taskId: task.id)) {
                    Image(systemName: "circle")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(task.color)
                        .frame(width: 22)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : task.typeIcon)
                    .font(.system(size: 15))
                    .foregroundStyle(task.isDone ? .green : task.color)
                    .frame(width: 22)
            }

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
    ReInspireEntry(date: .now, snapshot: .placeholder)
}

#Preview(as: .systemLarge) {
    TasksWidget()
} timeline: {
    ReInspireEntry(date: .now, snapshot: .placeholder)
}
