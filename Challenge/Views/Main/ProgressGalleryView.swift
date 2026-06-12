import SwiftUI
import Supabase

// MARK: - Progress Photo Gallery (#16)
// Groups photo reports per activity into a before → after timeline.

struct GalleryActivity: Identifiable {
    let id: UUID
    let title: String
    let typeIcon: String
    var photos: [GalleryPhoto]   // chronological (oldest first)

    var first: GalleryPhoto? { photos.first }
    var last: GalleryPhoto? { photos.last }
    var hasBeforeAfter: Bool { photos.count >= 2 }
}

struct GalleryPhoto: Identifiable {
    let id: UUID
    let url: String
    let date: Date
}

@Observable
final class ProgressGalleryViewModel {
    var activities: [GalleryActivity] = []
    var isLoading = true
    var errorMessage: String?

    func load() async {
        guard let user = AuthService.shared.currentUser else { isLoading = false; return }
        do {
            // 1. Activities (id → title, type)
            struct ActRow: Decodable { let id: UUID; let title: String; let type: String }
            let acts: [ActRow] = try await supabase
                .from("activities")
                .select("id,title,type")
                .eq("user_id", value: user.id.uuidString)
                .execute()
                .value
            let actMap = Dictionary(uniqueKeysWithValues: acts.map { ($0.id, $0) })
            let ids = acts.map { $0.id.uuidString }
            guard !ids.isEmpty else { activities = []; isLoading = false; return }

            // 2. Reports with photos
            struct RepRow: Decodable {
                let id: UUID; let activityId: UUID; let photoURL: String?; let createdAt: Date
                enum CodingKeys: String, CodingKey {
                    case id; case activityId = "activity_id"
                    case photoURL = "photo_url"; case createdAt = "created_at"
                }
            }
            let reports: [RepRow] = try await supabase
                .from("reports")
                .select("id,activity_id,photo_url,created_at")
                .in("activity_id", values: ids)
                .not("photo_url", operator: .is, value: "null")
                .order("created_at", ascending: true)
                .execute()
                .value

            // 3. Group
            var grouped: [UUID: GalleryActivity] = [:]
            for r in reports {
                guard let url = r.photoURL, !url.isEmpty, let act = actMap[r.activityId] else { continue }
                let photo = GalleryPhoto(id: r.id, url: url, date: r.createdAt)
                if grouped[r.activityId] == nil {
                    grouped[r.activityId] = GalleryActivity(
                        id: act.id,
                        title: act.title,
                        typeIcon: ActivityType(rawValue: act.type)?.icon ?? "photo",
                        photos: []
                    )
                }
                grouped[r.activityId]?.photos.append(photo)
            }
            activities = grouped.values
                .filter { !$0.photos.isEmpty }
                .sorted { ($0.photos.count, $0.title) > ($1.photos.count, $1.title) }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct ProgressGalleryView: View {
    @State private var vm = ProgressGalleryViewModel()

    var body: some View {
        ZStack {
            Color.white.ignoresSafeArea()
            if vm.isLoading {
                ProgressView()
            } else if vm.activities.isEmpty {
                emptyState
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 24) {
                        ForEach(Array(vm.activities.enumerated()), id: \.element.id) { index, activity in
                            NavigationLink(destination: ActivityGalleryDetail(activity: activity)) {
                                GalleryCard(activity: activity)
                            }
                            .buttonStyle(.haptic)
                            .appearEffect(delay: 0.05 + Double(index) * 0.08)
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.vertical, 16)
                    .readableWidth()
                }
            }
        }
        .navigationTitle("Progress")
        .navigationBarTitleDisplayMode(.inline)
        .task { await vm.load() }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("📸").font(.system(size: 56))
            Text("No progress photos yet")
                .font(.manrope(.bold, size: 18))
            Text("Submit photo reports to build your before/after timeline")
                .font(.manrope(.medium, size: 14))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 40)
    }
}

// MARK: - Card (preview with before/after thumbnails)

private struct GalleryCard: View {
    let activity: GalleryActivity

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: activity.typeIcon)
                    .foregroundStyle(Color(hex: "4580FF"))
                Text(activity.title)
                    .font(.manrope(.bold, size: 16))
                    .foregroundColor(.black)
                Spacer()
                Text("\(activity.photos.count) photos")
                    .font(.manrope(.medium, size: 12))
                    .foregroundColor(.black.opacity(0.4))
            }

            if activity.hasBeforeAfter, let first = activity.first, let last = activity.last {
                HStack(spacing: 8) {
                    GalleryThumb(url: first.url, label: "Before", date: first.date)
                    Image(systemName: "arrow.right")
                        .foregroundStyle(.black.opacity(0.3))
                    GalleryThumb(url: last.url, label: "After", date: last.date)
                }
            } else if let only = activity.first {
                GalleryThumb(url: only.url, label: "Latest", date: only.date)
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 18).fill(Color.black.opacity(0.03)))
    }
}

private struct GalleryThumb: View {
    let url: String
    let label: String
    let date: Date

    var body: some View {
        VStack(spacing: 4) {
            AsyncImage(url: URL(string: url)) { phase in
                switch phase {
                case .success(let img): img.resizable().scaledToFill()
                case .failure: Color.black.opacity(0.05).overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                default: Color.black.opacity(0.05).overlay(ProgressView())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Text(label)
                .font(.manrope(.bold, size: 12))
                .foregroundColor(.black.opacity(0.7))
            Text(date, style: .date)
                .font(.manrope(.medium, size: 10))
                .foregroundColor(.black.opacity(0.4))
        }
    }
}

// MARK: - Detail timeline

private struct ActivityGalleryDetail: View {
    let activity: GalleryActivity

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                if activity.hasBeforeAfter, let first = activity.first, let last = activity.last {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Before & After")
                            .font(.manrope(.bold, size: 18))
                        HStack(spacing: 10) {
                            GalleryThumb(url: first.url, label: "Before", date: first.date)
                            GalleryThumb(url: last.url, label: "After", date: last.date)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Timeline")
                        .font(.manrope(.bold, size: 18))
                    ForEach(activity.photos.reversed()) { photo in
                        VStack(alignment: .leading, spacing: 6) {
                            AsyncImage(url: URL(string: photo.url)) { phase in
                                switch phase {
                                case .success(let img): img.resizable().scaledToFit()
                                case .failure: Color.black.opacity(0.05).frame(height: 200)
                                default: Color.black.opacity(0.05).frame(height: 200).overlay(ProgressView())
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                            Text(photo.date, format: .dateTime.day().month().year().hour().minute())
                                .font(.manrope(.medium, size: 12))
                                .foregroundColor(.black.opacity(0.45))
                        }
                    }
                }
            }
            .padding(22)
            .readableWidth()
        }
        .navigationTitle(activity.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
