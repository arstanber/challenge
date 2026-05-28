import SwiftUI

struct ActivitiesView: View {
    @State private var vm = ActivitiesViewModel()
    @Environment(AuthService.self) private var authService
    @State private var showCreate = false
    @State private var showPlanner = false
    @State private var selectedTab = 0

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

                if vm.isLoading && activities.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if activities.isEmpty {
                    EmptyActivitiesView(isParentTab: selectedTab == 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(activities) { activity in
                            NavigationLink(destination: ActivityDetailView(activity: activity)) {
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
                                        Task { await vm.deleteActivity(activity) }
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await vm.loadActivities() }
                }
            }
            .navigationTitle("Challenge")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 4) {
                        // AI Planner button
                        Button {
                            showPlanner = true
                        } label: {
                            Image(systemName: "sparkles")
                                .font(.title3)
                                .foregroundStyle(.orange)
                        }
                        // Manual create button
                        Button {
                            if vm.canCreateMore { showCreate = true }
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
            .alert("Error", isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            )) {
                Button("OK") { vm.errorMessage = nil }
            } message: {
                Text(vm.errorMessage ?? "")
            }
        }
        .task { await vm.loadActivities() }
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
