import WidgetKit
import SwiftUI

struct ChallengeEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> ChallengeEntry {
        ChallengeEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping (ChallengeEntry) -> Void) {
        let snapshot = context.isPreview ? .placeholder : (WidgetDataStore.load() ?? .empty)
        completion(ChallengeEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ChallengeEntry>) -> Void) {
        let snapshot = WidgetDataStore.load() ?? .empty
        let entry = ChallengeEntry(date: Date(), snapshot: snapshot)
        // Refresh again at the next hour boundary as a safety net; the app also
        // pushes reloads via WidgetCenter whenever data changes.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}
