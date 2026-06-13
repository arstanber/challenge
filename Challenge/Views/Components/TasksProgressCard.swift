import SwiftUI

/// "Прогресс за месяц" -- a dot heatmap where each dot is one calendar day of
/// the current month. Filled (orange) = the day met the daily goal; an empty
/// past day stays gray; future days are faint; today gets a ring.
///
/// `monthDays[i]` corresponds to day `i + 1`. The view is width-adaptive: it
/// always lays the dots out in 10 columns (June -> a clean 3x10), sizing each
/// dot to fill the available width.
struct TasksProgressCard: View {
    /// Per-day goal-met flags for the current month (index i = day i+1).
    let monthDays: [Bool]
    /// 1-based day of the month for "today" (drives the highlight + future cut).
    var todayDay: Int = Calendar.current.component(.day, from: Date())

    private static let columns = 10
    private static let active = Color(red: 0.980, green: 0.325, blue: 0.110)

    private var metCount: Int { monthDays.prefix(todayDay).filter { $0 }.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("Прогресс за месяц")
                    .font(.manrope(.bold, size: 20))
                    .foregroundStyle(.primary)
                Spacer()
                Text("\(metCount)/\(monthDays.count)")
                    .font(.manrope(.extraBold, size: 16))
                    .foregroundStyle(Self.active)
            }

            DotGrid(monthDays: monthDays, todayDay: todayDay,
                    columns: Self.columns, active: Self.active)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
                Image("star2")
                    .resizable()
                    .scaledToFill()
                    .frame(width: 320, height: 320)
                    .opacity(0.05)
                    .offset(x: 90, y: -40)
                    .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        )
    }
}

// MARK: - Dot grid

private struct DotGrid: View {
    let monthDays: [Bool]
    let todayDay: Int
    let columns: Int
    let active: Color

    private let spacing: CGFloat = 5

    var body: some View {
        // Flexible columns let LazyVGrid size each cell to the available width;
        // every dot is locked square via aspectRatio, so the grid's height
        // follows naturally without any manual estimation.
        let cols = Array(repeating: GridItem(.flexible(), spacing: spacing), count: columns)
        LazyVGrid(columns: cols, spacing: spacing) {
            ForEach(monthDays.indices, id: \.self) { index in
                Dot(met: monthDays[index],
                    isToday: index + 1 == todayDay,
                    isFuture: index + 1 > todayDay,
                    active: active)
            }
        }
    }
}

private struct Dot: View {
    let met: Bool
    let isToday: Bool
    let isFuture: Bool
    let active: Color

    var body: some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(fill)
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(active, lineWidth: 2)
                }
            }
    }

    private var fill: Color {
        if met { return active }
        if isFuture { return Color.primary.opacity(0.04) }
        return Color.primary.opacity(0.09)
    }
}

// MARK: - Preview

#Preview {
    ZStack {
        Color(.systemBackground).ignoresSafeArea()
        TasksProgressCard(
            monthDays: [true, true, false, true, true, true, true, false, true, true,
                        true, false, true, true, true, true, true, false, true, true,
                        true, true, false, true, false, false, false, false, false, false],
            todayDay: 13
        )
        .padding(22)
    }
}
