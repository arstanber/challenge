import WidgetKit
import SwiftUI

struct ProgressTodayWidget: Widget {
    let kind = "ProgressTodayWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            ProgressTodayWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { WidgetStarBackground() }
        }
        .configurationDisplayName("Today's Progress")
        .description("Your completion versus today's goal, with a nudge.")
        .supportedFamilies([.systemSmall])
    }
}

struct ProgressTodayWidgetView: View {
    let snapshot: WidgetSnapshot

    private let badgeGreen = Color(red: 0.384, green: 0.867, blue: 0.494) // #62DD7E

    private var percent: Double {
        guard snapshot.dailyGoal > 0 else { return 0 }
        return Double(snapshot.todayDone) / Double(snapshot.dailyGoal) * 100
    }

    private var percentText: String {
        let r = (percent * 10).rounded() / 10
        if r == r.rounded() { return "\(Int(r))%" }
        return String(format: "%.1f", r).replacingOccurrences(of: ".", with: ",") + "%"
    }

    private var motivation: String {
        if snapshot.todayDone == 0 { return "Let's go 💪" }
        if snapshot.goalReached { return "Goal done ✅" }
        return "Doing great 🔥"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Progress")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 22, weight: .bold))
                Text(percentText)
                    .font(.system(size: 34, weight: .heavy, design: .rounded))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            }
            .foregroundStyle(.primary)

            Text(motivation)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.black)
                .lineLimit(1)
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Capsule().fill(badgeGreen))

            Spacer(minLength: 0)

            Text("reInspire")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }
}

#Preview(as: .systemSmall) {
    ProgressTodayWidget()
} timeline: {
    ReInspireEntry(date: .now, snapshot: .placeholder)
}
