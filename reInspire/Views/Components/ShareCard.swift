import SwiftUI
import UIKit

// MARK: - Share card kind

/// What a share card depicts. Drives the body of `ShareCardView`.
enum ShareCardKind {
    /// The user's current global streak (with their best for context).
    case streak(days: Int, best: Int)
    /// A single task the user just completed.
    case taskDone(title: String, streak: Int)
}

// MARK: - Share card view

/// A 9:16 branded card rendered to an image and handed to the system share
/// sheet (Instagram, Stories, Telegram, WhatsApp, Save Image, etc). Sized for
/// Instagram Stories so it drops in without cropping.
struct ShareCardView: View {
    let kind: ShareCardKind
    /// Optional user label shown in the footer.
    var name: String?

    /// Base layout size; the renderer upscales this to ~1080x1920.
    static let size = CGSize(width: 360, height: 640)

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                Text("reInspire.")
                    .font(.manrope(.extraBold, size: 22))
                    .foregroundStyle(.white)
                    .padding(.top, 44)

                Spacer()

                content

                Spacer()

                footer
                    .padding(.bottom, 44)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }

    // MARK: Background

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: "1c1638"), Color(hex: "0c0a18")],
                startPoint: .top, endPoint: .bottom
            )
            Circle()
                .fill(Color(hex: "7c4df0").opacity(0.40))
                .frame(width: 340, height: 340)
                .blur(radius: 100)
                .offset(y: -190)
        }
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 6) {
            if let name, !name.isEmpty {
                Text(name)
                    .font(.manrope(.semiBold, size: 15))
                    .foregroundStyle(.white.opacity(0.7))
            }
            Text("thechallenges.app")
                .font(.manrope(.medium, size: 13))
                .foregroundStyle(.white.opacity(0.4))
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch kind {
        case let .streak(days, best):
            streakContent(days: days, best: best)
        case let .taskDone(title, streak):
            taskContent(title: title, streak: streak)
        }
    }

    private func streakContent(days: Int, best: Int) -> some View {
        VStack(spacing: 14) {
            Text("🔥")
                .font(.system(size: 92))

            Text("\(days)")
                .font(.manrope(.extraBold, size: 104))
                .foregroundStyle(
                    LinearGradient(colors: [Color(hex: "ffce54"), Color(hex: "ff7a18")],
                                   startPoint: .top, endPoint: .bottom)
                )

            Text(days == 1 ? "день подряд" : "дней подряд")
                .font(.manrope(.bold, size: 22))
                .foregroundStyle(.white)

            if best > days {
                Text("Рекорд: \(best)")
                    .font(.manrope(.medium, size: 15))
                    .foregroundStyle(.white.opacity(0.55))
                    .padding(.top, 4)
            }
        }
    }

    private func taskContent(title: String, streak: Int) -> some View {
        VStack(spacing: 20) {
            ZStack {
                Circle()
                    .fill(Color(hex: "22c55e").opacity(0.18))
                    .frame(width: 132, height: 132)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Color(hex: "22c55e"))
            }

            Text("Задача выполнена")
                .font(.manrope(.extraBold, size: 26))
                .foregroundStyle(.white)

            Text(title)
                .font(.manrope(.medium, size: 18))
                .foregroundStyle(.white.opacity(0.75))
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .padding(.horizontal, 36)

            if streak > 0 {
                HStack(spacing: 6) {
                    Text("🔥")
                    Text("\(streak) подряд")
                        .font(.manrope(.semiBold, size: 16))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(.white.opacity(0.10), in: Capsule())
            }
        }
    }
}

// MARK: - Rendering

enum ShareCardRenderer {
    /// Renders a card to a high-resolution opaque image (~1080x1920).
    @MainActor
    static func render(_ kind: ShareCardKind, name: String?) -> UIImage? {
        let card = ShareCardView(kind: kind, name: name)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1080 / ShareCardView.size.width   // -> 1080x1920
        renderer.isOpaque = true
        return renderer.uiImage
    }
}

// MARK: - Instagram Stories

/// One-tap sharing of a rendered card straight into the Instagram Stories
/// composer. Falls back to the system share sheet (via the completion flag)
/// when Instagram is not installed.
enum InstagramStoryShare {
    /// Opens Instagram Stories with `image` preloaded as the story background.
    /// `completion(false)` means Instagram could not be opened -- the caller
    /// should fall back to the system share sheet.
    @MainActor
    static func share(image: UIImage, completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        let appID = Bundle.main.bundleIdentifier ?? "com.reinspire"
        // `open` does not consult LSApplicationQueriesSchemes, so no Info.plist
        // entry is needed; a missing Instagram simply yields success == false.
        guard let url = URL(string: "instagram-stories://share?source_application=\(appID)"),
              let data = image.pngData() else {
            completion(false)
            return
        }
        let items: [[String: Any]] = [[
            "com.instagram.sharedSticker.backgroundImage": data
        ]]
        UIPasteboard.general.setItems(items, options: [
            .expirationDate: Date().addingTimeInterval(60 * 5)
        ])
        UIApplication.shared.open(url, options: [:], completionHandler: completion)
    }
}

// MARK: - Share sheet bridge

/// Wraps a rendered image so it can drive a `.sheet(item:)` or
/// `.confirmationDialog(item:)`.
struct ShareableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// Minimal bridge handing items to the system share sheet (Instagram, Stories,
/// Telegram, WhatsApp, Save Image, etc).
struct ShareCardSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

// MARK: - Destination chooser

extension View {
    /// Presents an "Instagram Stories vs. other apps" chooser for `pending`.
    /// Picking Instagram opens it directly; "other apps" (and the Instagram
    /// fallback when it is not installed) opens the system share sheet.
    func shareDestinationDialog(pending: Binding<ShareableImage?>,
                                sheet: Binding<ShareableImage?>) -> some View {
        modifier(ShareDestinationDialog(pending: pending, sheet: sheet))
    }
}

private struct ShareDestinationDialog: ViewModifier {
    @Binding var pending: ShareableImage?
    @Binding var sheet: ShareableImage?

    private var isPresented: Binding<Bool> {
        Binding(get: { pending != nil }, set: { if !$0 { pending = nil } })
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Поделиться", isPresented: isPresented, presenting: pending) { item in
                Button("Instagram Stories") {
                    InstagramStoryShare.share(image: item.image) { ok in
                        if !ok { sheet = item }
                    }
                }
                Button("Другие приложения") { sheet = item }
                Button("Отмена", role: .cancel) {}
            }
            .sheet(item: $sheet) { item in
                ShareCardSheet(items: [item.image])
            }
    }
}

#Preview {
    VStack {
        ShareCardView(kind: .streak(days: 47, best: 60), name: "Арслан")
            .scaleEffect(0.5)
        ShareCardView(kind: .taskDone(title: "Пробежка 5 км", streak: 12), name: "Арслан")
            .scaleEffect(0.5)
    }
}
