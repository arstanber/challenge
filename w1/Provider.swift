import WidgetKit
import SwiftUI

struct ReInspireEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> ReInspireEntry {
        ReInspireEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (ReInspireEntry) -> Void) {
        let snapshot = context.isPreview ? .placeholder : (WidgetDataStore.load() ?? .empty)
        completion(ReInspireEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ReInspireEntry>) -> Void) {
        let snapshot = WidgetDataStore.load() ?? .empty
        let entry = ReInspireEntry(date: Date(), snapshot: snapshot)
        // Refresh again at the next hour boundary as a safety net; the app also
        // pushes reloads via WidgetCenter whenever data changes.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}
