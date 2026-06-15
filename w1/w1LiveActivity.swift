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

// MARK: - Attributes (mirror of reInspire/Models/ReInspireActivityAttributes.swift)

struct ReInspireActivityAttributes: ActivityAttributes {
    var dailyGoal: Int
    struct ContentState: Codable, Hashable {
        var todayDone: Int
        var streakCurrent: Int
        var nextTaskTitle: String
        var goalReached: Bool
    }
}

// MARK: - Palette

private enum DI {
    static let accent = Color(hex: "4580FF")   // primary progress
    static let done = Color.green              // goal reached
    static let streak = Color(hex: "FF8A3D")   // softened flame (secondary)
}

// MARK: - Progress ring (shared by island + lock screen)

private struct DIProgressRing: View {
    let done: Int
    let goal: Int
    let reached: Bool
    var size: CGFloat = 22
    var lineWidth: CGFloat = 3
    var fontSize: CGFloat = 11
    /// When false, the count label is hidden (used in the minimal presentation).
    var showLabel: Bool = true

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(done) / Double(goal), 1)
    }
    private var tint: Color { reached ? DI.done : DI.accent }

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.22), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: progress)
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if reached {
                Image(systemName: "checkmark")
                    .font(.system(size: fontSize, weight: .bold))
                    .foregroundStyle(tint)
            } else if showLabel {
                Text("\(done)")
                    .font(.system(size: fontSize, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: size, height: size)
    }
}

// MARK: - Streak pill (secondary metric)

private struct DIStreak: View {
    let value: Int
    var iconSize: CGFloat = 13
    var fontSize: CGFloat = 13
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "flame.fill")
                .font(.system(size: iconSize, weight: .bold))
            Text("\(value)")
                .font(.system(size: fontSize, weight: .bold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(DI.streak)
    }
}

// MARK: - Widget

struct w1LiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReInspireActivityAttributes.self) { context in
            LockScreenBanner(attrs: context.attributes, state: context.state)
                .activityBackgroundTint(DI.accent.opacity(0.12))
                .activitySystemActionForegroundColor(DI.accent)

        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    DIProgressRing(
                        done: context.state.todayDone,
                        goal: context.attributes.dailyGoal,
                        reached: context.state.goalReached,
                        size: 40, lineWidth: 4, fontSize: 17
                    )
                    .padding(.leading, 4)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(spacing: 0) {
                        DIStreak(value: context.state.streakCurrent, iconSize: 15, fontSize: 17)
                        Text("\(context.state.todayDone)/\(context.attributes.dailyGoal)")
                            .font(.system(.caption, design: .rounded).weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.state.goalReached {
                        Label("Цель дня выполнена!", systemImage: "checkmark.seal.fill")
                            .font(.system(.subheadline, design: .rounded).weight(.semibold))
                            .foregroundStyle(.green)
                    } else {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.circle.fill")
                                .foregroundStyle(DI.accent)
                            Text(context.state.nextTaskTitle.isEmpty ? "Открой приложение" : context.state.nextTaskTitle)
                                .font(.system(.subheadline, design: .rounded))
                                .lineLimit(1)
                        }
                    }
                }
            } compactLeading: {
                DIStreak(value: context.state.streakCurrent, iconSize: 12, fontSize: 13)
            } compactTrailing: {
                DIProgressRing(
                    done: context.state.todayDone,
                    goal: context.attributes.dailyGoal,
                    reached: context.state.goalReached,
                    size: 20, lineWidth: 2.5, fontSize: 11
                )
            } minimal: {
                DIProgressRing(
                    done: context.state.todayDone,
                    goal: context.attributes.dailyGoal,
                    reached: context.state.goalReached,
                    size: 20, lineWidth: 2.5, fontSize: 10, showLabel: false
                )
            }
            .widgetURL(URL(string: "reinspire://open"))
            .keylineTint(DI.accent)
        }
    }
}

// MARK: - Lock Screen Banner

private struct LockScreenBanner: View {
    let attrs: ReInspireActivityAttributes
    let state: ReInspireActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 16) {
            DIProgressRing(
                done: state.todayDone,
                goal: attrs.dailyGoal,
                reached: state.goalReached,
                size: 44, lineWidth: 5, fontSize: 15
            )

            VStack(alignment: .leading, spacing: 3) {
                if state.goalReached {
                    Text("Цель дня выполнена!")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(.green)
                } else {
                    Text(state.nextTaskTitle.isEmpty ? "Открой приложение, чтобы продолжить" : state.nextTaskTitle)
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                }
                Text("\(state.todayDone) из \(attrs.dailyGoal) выполнено · стрик \(state.streakCurrent) 🔥")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: - Previews

extension ReInspireActivityAttributes {
    static var preview: Self { .init(dailyGoal: 3) }
}
extension ReInspireActivityAttributes.ContentState {
    static var inProgress: Self {
        .init(todayDone: 1, streakCurrent: 7, nextTaskTitle: "Утренняя зарядка", goalReached: false)
    }
    static var reached: Self {
        .init(todayDone: 3, streakCurrent: 7, nextTaskTitle: "", goalReached: true)
    }
}

#Preview("Lock Screen", as: .content, using: ReInspireActivityAttributes.preview) {
    w1LiveActivity()
} contentStates: {
    ReInspireActivityAttributes.ContentState.inProgress
    ReInspireActivityAttributes.ContentState.reached
}

#Preview("Dynamic Island Expanded", as: .dynamicIsland(.expanded), using: ReInspireActivityAttributes.preview) {
    w1LiveActivity()
} contentStates: {
    ReInspireActivityAttributes.ContentState.inProgress
    ReInspireActivityAttributes.ContentState.reached
}
