import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Color(hex:) for widget target
// (The main app has this in OnboardingView.swift; widgets can't import the app module.)
private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default: (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(.sRGB, red: Double(r)/255, green: Double(g)/255,
                  blue: Double(b)/255, opacity: Double(a)/255)
    }
}

// MARK: - Attributes (mirror of Challenge/Models/ChallengeActivityAttributes.swift)

struct ChallengeActivityAttributes: ActivityAttributes {
    var dailyGoal: Int
    struct ContentState: Codable, Hashable {
        var todayDone: Int
        var streakCurrent: Int
        var nextTaskTitle: String
        var goalReached: Bool
    }
}

// MARK: - Widget

struct w1LiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ChallengeActivityAttributes.self) { context in
            LockScreenBanner(attrs: context.attributes, state: context.state)
                .activityBackgroundTint(Color(hex: "4580FF").opacity(0.12))
                .activitySystemActionForegroundColor(Color(hex: "4580FF"))

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 6) {
                        Image(systemName: "flame.fill").foregroundStyle(.orange)
                        Text("\(context.state.streakCurrent)")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .foregroundStyle(.orange)
                    }
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("\(context.state.todayDone)/\(context.attributes.dailyGoal)")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .foregroundStyle(context.state.goalReached ? .green : Color(hex: "4580FF"))
                        .padding(.trailing, 4)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.goalReached {
                        Label("Daily goal reached!", systemImage: "checkmark.seal.fill")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.green)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundStyle(Color(hex: "4580FF"))
                            Text(context.state.nextTaskTitle)
                                .font(.system(.subheadline, design: .rounded))
                                .lineLimit(1)
                        }
                    }
                }
            } compactLeading: {
                Image(systemName: "flame.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 13, weight: .bold))
            } compactTrailing: {
                Text("\(context.state.todayDone)/\(context.attributes.dailyGoal)")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(context.state.goalReached ? .green : Color(hex: "4580FF"))
                    .monospacedDigit()
            } minimal: {
                Image(systemName: context.state.goalReached ? "checkmark.seal.fill" : "flame.fill")
                    .foregroundStyle(context.state.goalReached ? .green : .orange)
                    .font(.system(size: 13, weight: .bold))
            }
            .widgetURL(URL(string: "challenge://open"))
            .keylineTint(Color(hex: "4580FF"))
        }
    }
}

// MARK: - Lock Screen Banner

private struct LockScreenBanner: View {
    let attrs: ChallengeActivityAttributes
    let state: ChallengeActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .stroke(Color(hex: "4580FF").opacity(0.2), lineWidth: 5)
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        state.goalReached ? Color.green : Color(hex: "4580FF"),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                if state.goalReached {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.green)
                } else {
                    Text("\(state.todayDone)")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                }
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 3) {
                if state.goalReached {
                    Text("Daily goal reached!")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(.green)
                } else {
                    Text(state.nextTaskTitle.isEmpty ? "Open app to continue" : state.nextTaskTitle)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                }
                Text("\(state.todayDone) of \(attrs.dailyGoal) done · \(state.streakCurrent)-day streak 🔥")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var progress: Double {
        guard attrs.dailyGoal > 0 else { return 0 }
        return min(Double(state.todayDone) / Double(attrs.dailyGoal), 1.0)
    }
}

// MARK: - Previews

extension ChallengeActivityAttributes {
    static var preview: Self { .init(dailyGoal: 3) }
}
extension ChallengeActivityAttributes.ContentState {
    static var inProgress: Self {
        .init(todayDone: 1, streakCurrent: 7, nextTaskTitle: "Morning workout", goalReached: false)
    }
    static var reached: Self {
        .init(todayDone: 3, streakCurrent: 7, nextTaskTitle: "", goalReached: true)
    }
}

#Preview("Lock Screen", as: .content, using: ChallengeActivityAttributes.preview) {
    w1LiveActivity()
} contentStates: {
    ChallengeActivityAttributes.ContentState.inProgress
    ChallengeActivityAttributes.ContentState.reached
}

#Preview("Dynamic Island Expanded", as: .dynamicIsland(.expanded), using: ChallengeActivityAttributes.preview) {
    w1LiveActivity()
} contentStates: {
    ChallengeActivityAttributes.ContentState.inProgress
    ChallengeActivityAttributes.ContentState.reached
}
