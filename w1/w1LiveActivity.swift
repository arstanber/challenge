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

struct LiveTask: Codable, Hashable, Identifiable {
    var id: UUID
    var title: String
    var done: Bool
    var verifying: Bool
}

struct ReInspireActivityAttributes: ActivityAttributes {
    var dailyGoal: Int
    struct ContentState: Codable, Hashable {
        var todayDone: Int
        var streakCurrent: Int
        var nextTaskTitle: String
        var goalReached: Bool
        var tasks: [LiveTask]
        var flashApproved: Bool
        var timerTaskId: UUID?
        var timerTitle: String?
        var timerStartedAt: Date?
        var timerAccumulatedSeconds: Double?
        var timerTargetMinutes: Double?
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

// MARK: - Progress bar (expanded bottom)

private struct DIProgressBar: View {
    let done: Int
    let goal: Int
    let reached: Bool

    private var progress: Double {
        guard goal > 0 else { return 0 }
        return min(Double(done) / Double(goal), 1)
    }
    private var tint: Color { reached ? DI.done : DI.accent }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(tint.opacity(0.22))
                Capsule()
                    .fill(tint)
                    .frame(width: max(0, geo.size.width * progress))
            }
        }
        .frame(height: 4)
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

// MARK: - Compact indicator (spinner -> check -> ring)

private struct DICompactProgress: View {
    let state: ReInspireActivityAttributes.ContentState
    let goal: Int
    var showLabel: Bool = true

    private var anyVerifying: Bool { state.tasks.contains { $0.verifying } }

    var body: some View {
        if anyVerifying {
            ProgressView()
                .controlSize(.mini)
                .tint(DI.accent)
        } else if state.flashApproved {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DI.done)
                .transition(.scale.combined(with: .opacity))
        } else {
            DIProgressRing(
                done: state.todayDone, goal: goal, reached: state.goalReached,
                size: 20, lineWidth: 2.5, fontSize: showLabel ? 11 : 10, showLabel: showLabel
            )
        }
    }
}

// MARK: - Persisted task timer

private struct DITimerElapsed: View {
    let state: ReInspireActivityAttributes.ContentState
    var font: Font = .system(.caption, design: .rounded).weight(.bold)

    private var accumulated: TimeInterval {
        max(0, state.timerAccumulatedSeconds ?? 0)
    }

    private var displayStart: Date? {
        state.timerStartedAt?.addingTimeInterval(-accumulated)
    }

    var body: some View {
        if let displayStart {
            Text(timerInterval: displayStart...Date.distantFuture, countsDown: false)
                .font(font)
                .monospacedDigit()
        } else {
            Text(Self.format(accumulated))
                .font(font)
                .monospacedDigit()
        }
    }

    private static func format(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

// MARK: - Task row with checkbox (expanded list)

private struct DITaskRow: View {
    let task: LiveTask

    var body: some View {
        // Tap opens the task in the app. uuidString in our own scheme is always
        // a valid URL, so the force-unwrap cannot fail.
        Link(destination: URL(string: "reinspire://task/\(task.id.uuidString)")!) {
            HStack(spacing: 8) {
                Group {
                    if task.verifying {
                        ProgressView()
                            .controlSize(.small)
                            .tint(DI.accent)
                    } else {
                        Image(systemName: task.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(task.done ? DI.done : .secondary)
                            .contentTransition(.symbolEffect(.replace))
                    }
                }
                .frame(width: 18, height: 18)
                Text(task.title)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(task.done ? .secondary : .primary)
                    .strikethrough(task.done, color: .secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
        }
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
                    if context.state.timerTaskId != nil {
                        Image(systemName: "timer")
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(DI.accent)
                            .frame(width: 40, height: 40)
                            .padding(.leading, 4)
                    } else {
                        DIProgressRing(
                            done: context.state.todayDone,
                            goal: context.attributes.dailyGoal,
                            reached: context.state.goalReached,
                            size: 40, lineWidth: 4, fontSize: 17
                        )
                        .padding(.leading, 4)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.timerTaskId != nil {
                        DITimerElapsed(
                            state: context.state,
                            font: .system(.title3, design: .rounded).weight(.bold)
                        )
                        .foregroundStyle(DI.accent)
                        .padding(.trailing, 6)
                    } else {
                        VStack(spacing: 0) {
                            DIStreak(value: context.state.streakCurrent, iconSize: 15, fontSize: 17)
                            Text("\(context.state.todayDone)/\(context.attributes.dailyGoal)")
                                .font(.system(.caption, design: .rounded).weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                        .padding(.trailing, 6)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        if context.state.timerTaskId != nil {
                            HStack(spacing: 8) {
                                Image(systemName: context.state.timerStartedAt == nil ? "play.fill" : "pause.fill")
                                    .foregroundStyle(DI.accent)
                                Text(context.state.timerTitle ?? "Таймер")
                                    .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if let target = context.state.timerTargetMinutes {
                                    Text("цель \(Int(target)) мин")
                                        .font(.system(.caption2, design: .rounded))
                                        .foregroundStyle(.secondary)
                                }
                            }
                        } else if context.state.goalReached {
                            Label("Цель дня выполнена!", systemImage: "checkmark.seal.fill")
                                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                                .foregroundStyle(DI.done)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if context.state.tasks.isEmpty {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .foregroundStyle(DI.accent)
                                (context.state.nextTaskTitle.isEmpty
                                    ? Text("Открой приложение")
                                    : Text(context.state.nextTaskTitle))
                                    .font(.system(.subheadline, design: .rounded))
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                            }
                        } else {
                            ForEach(context.state.tasks.prefix(4)) { task in
                                DITaskRow(task: task)
                            }
                        }
                        DIProgressBar(
                            done: context.state.todayDone,
                            goal: context.attributes.dailyGoal,
                            reached: context.state.goalReached
                        )
                        .padding(.top, 2)
                    }
                }
            } compactLeading: {
                if context.state.timerTaskId != nil {
                    Image(systemName: "timer")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DI.accent)
                } else {
                    DIStreak(value: context.state.streakCurrent, iconSize: 12, fontSize: 13)
                }
            } compactTrailing: {
                if context.state.timerTaskId != nil {
                    DITimerElapsed(state: context.state)
                        .foregroundStyle(DI.accent)
                } else {
                    DICompactProgress(state: context.state, goal: context.attributes.dailyGoal)
                }
            } minimal: {
                if context.state.timerTaskId != nil {
                    Image(systemName: "timer")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DI.accent)
                } else {
                    DICompactProgress(state: context.state, goal: context.attributes.dailyGoal, showLabel: false)
                }
            }
            .widgetURL(context.state.timerTaskId.flatMap {
                URL(string: "reinspire://task/\($0.uuidString)")
            } ?? URL(string: "reinspire://open"))
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
            if state.timerTaskId != nil {
                Image(systemName: "timer")
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(DI.accent)
                    .frame(width: 44, height: 44)
                    .background(DI.accent.opacity(0.12), in: Circle())
            } else {
                DIProgressRing(
                    done: state.todayDone,
                    goal: attrs.dailyGoal,
                    reached: state.goalReached,
                    size: 44, lineWidth: 5, fontSize: 15
                )
            }

            VStack(alignment: .leading, spacing: 3) {
                if state.timerTaskId != nil {
                    Text(state.timerTitle ?? "Таймер")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .lineLimit(1)
                    HStack(spacing: 8) {
                        DITimerElapsed(state: state)
                            .foregroundStyle(DI.accent)
                        if state.timerStartedAt == nil {
                            Text("на паузе")
                                .font(.system(.caption, design: .rounded))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if state.goalReached {
                    Text("Цель дня выполнена!")
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                        .foregroundStyle(.green)
                } else {
                    (state.nextTaskTitle.isEmpty
                        ? Text("Открой приложение, чтобы продолжить")
                        : Text(state.nextTaskTitle))
                        .font(.system(.subheadline, design: .rounded).weight(.semibold))
                        .lineLimit(1)
                }
                if state.timerTaskId == nil {
                    Text("\(state.todayDone) из \(attrs.dailyGoal) выполнено · стрик \(state.streakCurrent) 🔥")
                        .font(.system(.caption, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        // Subtle star2 watermark so the banner reads as part of the same widget
        // family. The island itself can't take a background, only this banner.
        .background(alignment: .bottomTrailing) {
            Image("star2")
                .resizable()
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .frame(width: 96)
                .foregroundStyle(state.goalReached ? DI.done : DI.accent)
                .opacity(0.10)
                .offset(x: 16, y: 12)
                .allowsHitTesting(false)
        }
    }
}

// MARK: - Previews

extension ReInspireActivityAttributes {
    static var preview: Self { .init(dailyGoal: 3) }
}
extension ReInspireActivityAttributes.ContentState {
    private static let sampleTasks: [LiveTask] = [
        LiveTask(id: UUID(), title: "Утренняя зарядка", done: true, verifying: false),
        LiveTask(id: UUID(), title: "Прочитать 10 страниц", done: false, verifying: false),
        LiveTask(id: UUID(), title: "Медитация", done: false, verifying: false)
    ]
    static var inProgress: Self {
        .init(todayDone: 1, streakCurrent: 7, nextTaskTitle: "Прочитать 10 страниц",
              goalReached: false, tasks: sampleTasks, flashApproved: false)
    }
    static var verifying: Self {
        var t = sampleTasks
        t[1].verifying = true
        return .init(todayDone: 1, streakCurrent: 7, nextTaskTitle: "Прочитать 10 страниц",
                     goalReached: false, tasks: t, flashApproved: false)
    }
    static var reached: Self {
        .init(todayDone: 3, streakCurrent: 7, nextTaskTitle: "",
              goalReached: true, tasks: sampleTasks.map { var x = $0; x.done = true; return x },
              flashApproved: false)
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
    ReInspireActivityAttributes.ContentState.verifying
    ReInspireActivityAttributes.ContentState.reached
}

#Preview("Dynamic Island Compact", as: .dynamicIsland(.compact), using: ReInspireActivityAttributes.preview) {
    w1LiveActivity()
} contentStates: {
    ReInspireActivityAttributes.ContentState.inProgress
    ReInspireActivityAttributes.ContentState.verifying
    ReInspireActivityAttributes.ContentState.reached
}
