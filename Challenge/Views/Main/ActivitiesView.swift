import SwiftUI

struct ActivitiesView: View {
    @State private var vm = ActivitiesViewModel()
    @Environment(AuthService.self) private var authService
    @State private var showCreate = false
    @State private var showPlanner = false
    @State private var showPaywall = false
    @State private var selectedTab = 0
    @State private var deletingActivity: Activity?

    private var isChild: Bool { authService.currentUser?.role == .child }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isChild {
                    Picker("Tab", selection: $selectedTab) {
                        Text("Mine").tag(0)
                        Text("From parents").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                }

                let activities = selectedTab == 0 ? vm.myActivities : vm.parentActivities
                let standalones = selectedTab == 0 ? vm.standaloneActivities : vm.parentActivities
                let plans = selectedTab == 0 ? vm.planGroups : []

                if vm.isLoading && activities.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if activities.isEmpty {
                    EmptyActivitiesView(isParentTab: selectedTab == 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        // AI plan groups (only on "Mine" tab)
                        if !plans.isEmpty {
                            Section("My Plans") {
                                ForEach(plans) { group in
                                    PlanGroupRow(group: group) {
                                        Task { await vm.recalculateGlobalStreak() }
                                    }
                                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                }
                            }
                        }

                        // Standalone / parent activities
                        if !standalones.isEmpty {
                            Section(plans.isEmpty ? "" : "Individual") {
                                ForEach(standalones) { activity in
                                    NavigationLink(destination: ActivityDetailView(activity: activity, onReportSubmitted: {
                                        Task { await vm.recalculateGlobalStreak() }
                                    })) {
                                        ActivityRowView(activity: activity)
                                            .listRowInsets(EdgeInsets())
                                    }
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(Color.clear)
                                    .padding(.horizontal)
                                    .padding(.vertical, 4)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        if activity.status == .active {
                                            Button(role: .destructive) {
                                                Haptics.warning()
                                                deletingActivity = activity
                                            } label: {
                                                Label("Удалить", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await vm.loadActivities() }
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                GlobalStreakBanner(vm: vm)
            }
            .navigationTitle("Challenge")
            .hapticFeedback(.selection, trigger: selectedTab)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 4) {
                        // AI Planner button
                        Button {
                            Haptics.tap()
                            showPlanner = true
                        } label: {
                            Image(systemName: "sparkles")
                                .font(.title3)
                                .foregroundStyle(.orange)
                        }
                        // Manual create button
                        Button {
                            if vm.canCreateMore { Haptics.tap(); showCreate = true }
                            else { Haptics.warning(); showPaywall = true }
                        } label: {
                            if vm.canCreateMore {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                            } else {
                                Label("Upgrade", systemImage: "lock.circle.fill")
                                    .font(.caption)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $showCreate, onDismiss: {
                Task { await vm.loadActivities() }
            }) {
                CreateActivityView()
            }
            .sheet(isPresented: $showPlanner, onDismiss: {
                Task { await vm.loadActivities() }
            }) {
                GoalPlannerView()
            }
            .sheet(isPresented: $showPaywall) {
                NavigationStack { PremiumView() }
            }
            .sheet(item: $deletingActivity) { activity in
                DeleteReasonSheet(activityTitle: activity.title) { reason in
                    Task { await vm.deleteActivity(activity, reason: reason) }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK") { Haptics.tap(); vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
        .task { await vm.loadActivities() }
    }
}

// MARK: - Plan Group Row

struct PlanGroupRow: View {
    let group: ActivityPlanGroup
    let onReportSubmitted: () -> Void
    @State private var isExpanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header card
            Button {
                withAnimation(.spring(response: 0.3)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 12) {
                    // Plan icon
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.15))
                            .frame(width: 40, height: 40)
                        Image(systemName: "sparkles")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.orange)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(group.title)
                            .font(.subheadline.bold())
                            .foregroundStyle(.primary)
                            .multilineTextAlignment(.leading)
                        Text("\(group.completedCount) of \(group.totalCount) completed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    // Circular progress
                    ZStack {
                        Circle()
                            .stroke(Color(.systemGray5), lineWidth: 3)
                        Circle()
                            .trim(from: 0, to: group.progressFraction)
                            .stroke(group.isFullyCompleted ? Color.green : Color.orange, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                            .animation(.easeInOut, value: group.progressFraction)
                    }
                    .frame(width: 28, height: 28)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.background, in: RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .strokeBorder(Color.orange.opacity(0.25), lineWidth: 1)
                )
            }
            .buttonStyle(.haptic)

            // Expanded activity list
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(group.activities) { activity in
                        NavigationLink(destination: ActivityDetailView(activity: activity, onReportSubmitted: onReportSubmitted)) {
                            ActivityRowView(activity: activity)
                        }
                        .buttonStyle(.haptic)
                        .padding(.horizontal, 8)
                        .padding(.top, 6)
                    }
                }
                .padding(.bottom, 4)
            }
        }
    }
}

// MARK: - Global Streak Banner

struct GlobalStreakBanner: View {
    let vm: ActivitiesViewModel
    private let minPerDay = Constants.App.minDailyActivitiesForStreak

    var body: some View {
        HStack(spacing: 12) {
            // Flame icon with streak count
            HStack(spacing: 4) {
                Image(systemName: "flame.fill")
                    .foregroundStyle(vm.globalStreakCurrent > 0 ? .orange : .gray)
                Text("\(vm.globalStreakCurrent)")
                    .font(.title3.bold())
                    .foregroundStyle(vm.globalStreakCurrent > 0 ? .primary : .secondary)
                Text("days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider().frame(height: 24)

            // Today's progress toward next streak day
            VStack(alignment: .leading, spacing: 2) {
                let done = Swift.min(vm.todayCount, minPerDay)
                Text("Today: \(done)/\(minPerDay) to keep streak")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.systemGray5)).frame(height: 4)
                        Capsule()
                            .fill(vm.todayCount >= minPerDay ? Color.orange : Color.orange.opacity(0.5))
                            .frame(width: geo.size.width * Swift.min(Double(vm.todayCount) / Double(minPerDay), 1.0), height: 4)
                    }
                }
                .frame(height: 4)
            }

            Spacer()

            // Best
            if vm.globalStreakBest > 0 {
                VStack(spacing: 0) {
                    Image(systemName: "trophy.fill")
                        .font(.caption)
                        .foregroundStyle(.yellow)
                    Text("\(vm.globalStreakBest)")
                        .font(.caption.bold())
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

struct EmptyActivitiesView: View {
    let isParentTab: Bool

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: isParentTab ? "person.2.circle" : "flame.circle")
                .font(.system(size: 60))
                .foregroundStyle(.orange.opacity(0.5))
            Text(isParentTab ? "No assignments from parents yet" : "Start your first challenge")
                .font(.headline)
                .foregroundStyle(.secondary)
            if !isParentTab {
                VStack(spacing: 4) {
                    Text("Tap ✦ to let AI build a plan for you")
                        .font(.subheadline)
                        .foregroundStyle(.orange)
                    Text("or + to create manually")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

#Preview {
    ActivitiesView()
        .environment(AuthService.shared)
}
