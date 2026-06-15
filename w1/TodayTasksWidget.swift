import WidgetKit
import SwiftUI

struct TodayTasksWidget: Widget {
    let kind = "TodayTasksWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            TodayTasksWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { WidgetStarBackground() }
        }
        .configurationDisplayName("For Today")
        .description("The tasks still waiting for you today.")
        .supportedFamilies([.systemSmall])
    }
}

struct TodayTasksWidgetView: View {
    let snapshot: WidgetSnapshot

    private var pending: [String] {
        snapshot.tasks.filter { !$0.isDone }.map(\.title)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("For today")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            if pending.isEmpty {
                Spacer(minLength: 0)
                Text(snapshot.tasks.isEmpty ? "No tasks yet" : "All done ✅")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(.primary)
            } else {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(Array(pending.prefix(3).enumerated()), id: \.offset) { _, title in
                        Text(title)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .foregroundStyle(.primary)
                            // Long titles wrap onto a second line instead of
                            // truncating with an ellipsis.
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if pending.count > 3 {
                    Text("+\(pending.count - 3) more")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)

            Text("reInspire")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

#Preview(as: .systemSmall) {
    TodayTasksWidget()
} timeline: {
    ReInspireEntry(date: .now, snapshot: .placeholder)
}
