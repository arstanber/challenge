import WidgetKit
import SwiftUI

struct StreakWidget: Widget {
    let kind = "StreakWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            StreakWidgetView(snapshot: entry.snapshot)
                .containerBackground(for: .widget) { backgroundGradient }
        }
        .configurationDisplayName("Streak")
        .description("Your current daily streak at a glance.")
        .supportedFamilies([
            .systemSmall,
            .accessoryCircular,
            .accessoryInline,
            .accessoryRectangular
        ])
    }

    private var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [Color.orange.opacity(0.22), Color.red.opacity(0.12)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct StreakWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let snapshot: WidgetSnapshot

    var body: some View {
        switch family {
        case .accessoryCircular:
            accessoryCircular
        case .accessoryInline:
            Label("\(snapshot.streakCurrent) day streak", systemImage: "flame.fill")
        case .accessoryRectangular:
            accessoryRectangular
        default:
            small
        }
    }

    private var small: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                Text("Streak")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Text("\(snapshot.streakCurrent)")
                .font(.system(size: 52, weight: .heavy, design: .rounded))
                .foregroundStyle(.orange)
                .minimumScaleFactor(0.5)
                .lineLimit(1)
            Text(snapshot.streakCurrent == 1 ? "day" : "days")
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack(spacing: 4) {
                Image(systemName: "trophy.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                Text("Best \(snapshot.streakBest)")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessoryCircular: some View {
        ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "flame.fill")
                    .font(.system(size: 12))
                Text("\(snapshot.streakCurrent)")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
        }
    }

    private var accessoryRectangular: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .font(.title2)
            VStack(alignment: .leading, spacing: 1) {
                Text("\(snapshot.streakCurrent) day streak")
                    .font(.headline)
                Text("Best \(snapshot.streakBest) · \(snapshot.activeCount) active")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview(as: .systemSmall) {
    StreakWidget()
} timeline: {
    ChallengeEntry(date: .now, snapshot: .placeholder)
}
