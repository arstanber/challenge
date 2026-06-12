import SwiftUI

// MARK: - Reorder sheet
// Manual ordering of home-screen task cards: rows are the top-level active
// tasks; the new order lands in activities.sort_order when the sheet closes.

struct ReorderSheet: View {
    var vm: ActivitiesViewModel
    @Environment(\.dismiss) private var dismiss

    private var items: [Activity] {
        vm.myActivities.filter { $0.parentId == nil && $0.status == .active }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(items) { task in
                    HStack(spacing: 12) {
                        Image(systemName: task.type.icon)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(accent(task.type))
                            .frame(width: 26)
                        Text(task.title)
                            .font(.manrope(.medium, size: 16))
                            .lineLimit(1)
                    }
                    .padding(.vertical, 2)
                }
                .onMove { from, to in
                    Haptics.selection()
                    vm.moveTopLevel(fromOffsets: from, toOffset: to)
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle("Порядок задач")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Готово") { Haptics.tap(); dismiss() }
                        .font(.manrope(.semiBold, size: 16))
                }
            }
        }
        .onDisappear {
            Task { await vm.persistOrder() }
        }
    }

    private func accent(_ type: ActivityType) -> Color {
        switch type {
        case .challenge:  return Color(hex: "0048E2")
        case .goal:       return Color(hex: "2FB873")
        case .task:       return Color(hex: "FF7A00")
        case .habit:      return Color(hex: "8B5CF6")
        case .assignment: return Color(hex: "EC4899")
        }
    }
}
