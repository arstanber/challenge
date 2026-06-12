import SwiftUI
import Supabase
import PostgREST
import os.log

private let logger = Logger(subsystem: "com.challenge", category: "DoneTasksView")

// MARK: - Main View

struct DoneTasksView: View {
    @State private var completedActivities: [Activity] = []
    @State private var isLoading = true
    @Environment(\.dismiss) private var dismiss

    private let checkBlue = Color(red: 0.0, green: 0.282, blue: 0.886)

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()

            VStack(spacing: 0) {
                // Nav bar
                ZStack {
                    Text("The Challenge.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.black)
                    HStack {
                        Button { Haptics.tap(); dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .medium))
                                .foregroundColor(.black)
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 12)

                if isLoading {
                    Spacer()
                    ProgressView()
                    Spacer()
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 32) {
                            DoneHeaderView(count: completedActivities.count, checkBlue: checkBlue)

                            if completedActivities.isEmpty {
                                DoneEmptyState()
                            } else {
                                DoneTaskListView(activities: completedActivities)
                            }
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 16)
                        .padding(.bottom, 40)
                        .readableWidth()
                    }
                }
            }
        }
        .task { await loadCompleted() }
    }

    private func loadCompleted() async {
        guard let user = AuthService.shared.currentUser else {
            isLoading = false
            return
        }
        do {
            let all: [Activity] = try await supabase
                .from("activities")
                .select()
                .eq("user_id", value: user.id.uuidString)
                .eq("status", value: "completed")
                .order("created_at", ascending: false)
                .execute()
                .value
            completedActivities = all
        } catch {
            logger.error("DoneTasksView load error: \(error)")
        }
        isLoading = false
    }
}

// MARK: - Header

private struct DoneHeaderView: View {
    let count: Int
    let checkBlue: Color

    private static let headerFont = Font.system(size: 36, weight: .black).italic()

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 0) {
            Text("You have done ")
                .font(Self.headerFont)
                .foregroundColor(.black)
            Text("\(count)")
                .font(Self.headerFont)
                .foregroundColor(checkBlue)
            Text(" Tasks")
                .font(Self.headerFont)
                .foregroundColor(.black)
            Spacer(minLength: 0)
        }
        .lineLimit(3)
        .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Task list

private struct DoneTaskListView: View {
    let activities: [Activity]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(activities) { activity in
                DoneTaskRow(activity: activity)
            }
        }
    }
}

private struct DoneTaskRow: View {
    let activity: Activity

    private let checkBlue = Color(red: 0.0, green: 0.282, blue: 0.886)
    private let taskText = Color(red: 0.071, green: 0.071, blue: 0.071)
    private var category: TaskCategory { TaskCategorizer.category(for: activity) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                // Filled blue checkbox
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(checkBlue)
                        .frame(width: 24, height: 24)
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(activity.title)
                        .font(.system(size: 17, weight: .medium))
                        .foregroundColor(taskText.opacity(0.45))
                        .strikethrough(true, color: taskText.opacity(0.35))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(category.label)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(category.color)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(category.color.opacity(0.12))
                        )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)

            Rectangle()
                .fill(Color.black.opacity(0.15))
                .frame(height: 1)
        }
    }
}

// MARK: - Empty state

private struct DoneEmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundColor(.black.opacity(0.2))
            Text("No completed tasks yet")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.black.opacity(0.5))
            Text("Complete a task to see it here")
                .font(.system(size: 14))
                .foregroundColor(.black.opacity(0.35))
        }
        .padding(.top, 40)
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    DoneTasksView()
        .environment(AuthService.shared)
}
