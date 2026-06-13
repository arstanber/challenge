import WidgetKit
import SwiftUI

@main
struct w1Bundle: WidgetBundle {
    var body: some Widget {
        StreakWidget()
        TodayProgressWidget()
        TasksWidget()
        MonthProgressWidget()
        w1LiveActivity()
    }
}
