import SwiftUI

struct WorkspaceHomeView: View {
    let workspace: Workspace

    @State private var vm = ActivitiesViewModel()
    @Environment(\.dismiss) private var dismiss
    @AppStorage("requirePhotoVerification") private var requirePhoto = true

    @State private var showMenu = false
    @State private var showManualCreate = false
    @State private var showBySaying = false
    @State private var taskToComplete: Activity?

    private var activeTasks: [Activity] {
        (vm.myActivities + vm.parentActivities).filter { $0.status == .active }
    }

    private var categorySummary: [(category: TaskCategory, count: Int)] {
        var counts: [TaskCategory: Int] = [:]
        for activity in activeTasks {
            let cat = TaskCategorizer.category(for: activity)
            counts[cat, default: 0] += 1
        }
        return counts
            .map { ($0.key, $0.value) }
            .sorted { ($0.1, $1.0.label) > ($1.1, $0.0.label) }
            .prefix(4).map { $0 }
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Color.white.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 0) {
                    VStack(spacing: 32) {
                        // Header
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(workspace.name)
                                .font(.system(size: 32, weight: .semibold))
                                .foregroundColor(.black)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                            Spacer(minLength: 0)
                        }

                        if !categorySummary.isEmpty {
                            HomeCategorySummaryGrid(summary: categorySummary)
                        }

                        if vm.isLoading && activeTasks.isEmpty {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else if activeTasks.isEmpty {
                            WorkspaceEmptyState(workspaceName: workspace.name)
                        } else {
                            HomeTaskListView(activities: activeTasks) { activity in
                                if requirePhoto {
                                    taskToComplete = activity
                                } else {
                                    Task {
                                        await vm.markCompleted(activity)
                                        await vm.loadWorkspaceActivities(workspaceId: workspace.id)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 16)
                    .padding(.bottom, 120)
                    .readableWidth()
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                HStack {
                    Button { Haptics.tap(); dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.black)
                    }
                    Spacer()
                    Text("reInspire.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.black)
                    Spacer()
                    // Balance the X
                    Image(systemName: "xmark").opacity(0)
                        .font(.system(size: 16, weight: .medium))
                }
                .padding(.horizontal, 22)
                .padding(.vertical, 8)
                .background(Color.white)
            }
            .refreshable {
                await vm.loadWorkspaceActivities(workspaceId: workspace.id)
            }

            // FAB
            if !showMenu {
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        showMenu = true
                    }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(width: 68, height: 68)
                        .adaptiveGlassEffect(in: Circle())
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.trailing, 24)
                .padding(.bottom, 48)
            }

            // Backdrop + popup
            if showMenu {
                Color.black.opacity(0.25)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .hapticTap {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showMenu = false }
                    }

                VStack {
                    Spacer()
                    CreationMenuPopup(
                        onAIStepByStep: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showMenu = false }
                        },
                        onBySaying: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showMenu = false }
                            showBySaying = true
                        },
                        onByYourself: {
                            withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) { showMenu = false }
                            showManualCreate = true
                        }
                    )
                    .padding(.horizontal, 12)
                    .padding(.bottom, 32)
                    .readableWidth(480)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .task { await vm.loadWorkspaceActivities(workspaceId: workspace.id) }
        .sheet(isPresented: $showManualCreate, onDismiss: {
            Task { await vm.loadWorkspaceActivities(workspaceId: workspace.id) }
        }) {
            ByYourselfView(workspaceId: workspace.id)
        }
        .sheet(isPresented: $showBySaying, onDismiss: {
            Task { await vm.loadWorkspaceActivities(workspaceId: workspace.id) }
        }) {
            BySayingView(workspaceId: workspace.id)
        }
        .sheet(item: $taskToComplete) { activity in
            CompleteTaskView(activity: activity) {
                Task {
                    await vm.markCompleted(activity)
                    await vm.loadWorkspaceActivities(workspaceId: workspace.id)
                }
            }
        }
    }
}

// MARK: - Empty state

private struct WorkspaceEmptyState: View {
    let workspaceName: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(.black.opacity(0.2))
            Text("No tasks in \(workspaceName)")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.black.opacity(0.5))
            Text("Tap + to add your first task here")
                .font(.system(size: 14))
                .foregroundColor(.black.opacity(0.35))
        }
        .padding(.top, 40)
    }
}

// MARK: - Reuse HomeCategorySummaryGrid / HomeTaskListView
// These are defined in HomeView.swift as private, so we duplicate the minimal version here.

private struct HomeCategorySummaryGrid: View {
    let summary: [(category: TaskCategory, count: Int)]
    @Environment(\.horizontalSizeClass) private var hSizeClass

    var body: some View {
        LazyVGrid(columns: .adaptive(compact: 2, regular: 3, for: hSizeClass, spacing: 8), spacing: 8) {
            ForEach(summary, id: \.category.label) { item in
                HStack(spacing: 4) {
                    Text("\(item.count)")
                        .font(.system(size: 17, weight: .bold))
                        .foregroundColor(.black)
                    Text(item.category.label.capitalized)
                        .font(.system(size: 17, weight: .regular))
                        .foregroundColor(.black.opacity(0.5))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(item.category.color.opacity(0.12))
                )
            }
        }
    }
}

private struct HomeTaskListView: View {
    let activities: [Activity]
    let onComplete: (Activity) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(activities) { activity in
                HomeTaskRowView(activity: activity, onComplete: { onComplete(activity) })
            }
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.black.opacity(0.15), lineWidth: 0.5))
    }
}

private struct HomeTaskRowView: View {
    let activity: Activity
    let onComplete: () -> Void
    @State private var isCompleting = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isCompleting ? Color(red: 0, green: 0.280, blue: 0.886) : .white)
                        .frame(width: 24, height: 24)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isCompleting ? Color(red: 0, green: 0.280, blue: 0.886) : Color(red: 0.839, green: 0.839, blue: 0.839), lineWidth: 2)
                        )
                    if isCompleting {
                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundColor(.white)
                    }
                }
                .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isCompleting)
                .onTapGesture {
                    guard !isCompleting else { return }
                    Haptics.medium()
                    withAnimation { isCompleting = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.55) { onComplete() }
                }

                Text(activity.title)
                    .font(.custom("Manrope", size: 17).weight(.semibold))
                    .foregroundColor(Color(red: 0.071, green: 0.071, blue: 0.071))
                    .strikethrough(isCompleting, color: Color(red: 0.071, green: 0.071, blue: 0.071))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)
            Divider().background(Color.black.opacity(0.15))
        }
    }
}

#Preview {
    WorkspaceHomeView(workspace: Workspace(
        id: UUID(),
        userId: UUID(),
        name: "Work",
        createdAt: Date()
    ))
}
