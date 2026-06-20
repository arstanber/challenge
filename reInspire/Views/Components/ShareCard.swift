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

// MARK: - Theme & format

/// Brand colourway of a share card. Mirrors the Figma templates.
enum ShareCardTheme {
    case blue   // #0048e2 background, white ink + bright burst
    case light  // white background, black ink + ghost burst

    var background: Color {
        switch self {
        case .blue:  return Color(hex: "0048E2")
        case .light: return .white
        }
    }

    var ink: Color {
        switch self {
        case .blue:  return .white
        case .light: return .black
        }
    }

    /// Fill for secondary chips / muted text.
    var inkMuted: Color { ink.opacity(0.6) }
}

/// Output canvas of a share card.
enum ShareCardFormat {
    case story  // 1080x1920 (Instagram/TikTok Stories)
    case post   // 1080x1350 (Instagram feed 4:5)

    /// Native pixel size; the card is rendered at scale 1 into this size.
    var size: CGSize {
        switch self {
        case .story: return CGSize(width: 1080, height: 1920)
        case .post:  return CGSize(width: 1080, height: 1350)
        }
    }

    /// Wordmark top-left origin (from Figma).
    var wordmarkOrigin: CGPoint {
        switch self {
        case .story: return CGPoint(x: 139, y: 171)
        case .post:  return CGPoint(x: 73, y: 65)
        }
    }

    /// Burst image frame (from Figma, in canvas pixels). Overflows + clips.
    var burstFrame: CGRect {
        switch self {
        case .story: return CGRect(x: -337, y: 600, width: 1944, height: 1943)
        case .post:  return CGRect(x: -518, y: 35, width: 2181, height: 2179)
        }
    }

    /// Vertical centre (fraction of height) of the clean zone where the
    /// dynamic content sits, above the dense part of the burst.
    var contentCenterFraction: CGFloat {
        switch self {
        case .story: return 0.40
        case .post:  return 0.36
        }
    }
}

// MARK: - Share card view

/// A branded share card matching the Figma post/story templates: solid
/// background, "reInspire." wordmark top-left, a hand-drawn burst-checkmark
/// anchored bottom, and the dynamic streak/task content in the clean zone.
/// Rendered to an image and handed to the share sheet / Instagram Stories.
struct ShareCardView: View {
    let kind: ShareCardKind
    /// Optional user label shown in the footer.
    var name: String?
    var theme: ShareCardTheme = .blue
    var format: ShareCardFormat = .story
    private var size: CGSize { format.size }

    var body: some View {
        // The background defines a fixed canvas; every overlay is laid out
        // against it, so offsets/alignment resolve in true pixel space even
        // though the burst image overflows the frame.
        theme.background
            .frame(width: size.width, height: size.height)
            // Burst-checkmark (decorative), anchored per the template.
            .overlay(alignment: .topLeading) {
                Image("shareStar")
                    .resizable()
                    .scaledToFit()
                    .frame(width: format.burstFrame.width, height: format.burstFrame.height)
                    .offset(x: format.burstFrame.minX, y: format.burstFrame.minY)
            }
            // Wordmark, top-left.
            .overlay(alignment: .topLeading) {
                Text("reInspire.")
                    .font(.sfProDisplay(64, weight: .medium))
                    .foregroundStyle(theme.ink)
                    .offset(x: format.wordmarkOrigin.x, y: format.wordmarkOrigin.y)
            }
            // Dynamic content in the clean zone.
            .overlay {
                content
                    .offset(y: (format.contentCenterFraction - 0.5) * size.height)
            }
            // Footer / handle.
            .overlay(alignment: .bottom) {
                footer.padding(.bottom, 64)
            }
            .clipped()
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: 10) {
            if let name, !name.isEmpty {
                Text(name)
                    .font(.sfProDisplay(34, weight: .semibold))
                    .foregroundStyle(theme.ink.opacity(0.75))
            }
            Text("thechallenges.app")
                .font(.sfProDisplay(28, weight: .medium))
                .foregroundStyle(theme.inkMuted)
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
        VStack(spacing: 24) {
            Text("🔥")
                .font(.system(size: 200))

            Text("\(days)")
                .font(.sfProDisplay(300, weight: .bold))
                .foregroundStyle(theme.ink)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            Text(days == 1 ? "день подряд" : "дней подряд")
                .font(.sfProDisplay(64, weight: .semibold))
                .foregroundStyle(theme.ink)

            if best > days {
                Text("Рекорд: \(best)")
                    .font(.sfProDisplay(40, weight: .medium))
                    .foregroundStyle(theme.inkMuted)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, 80)
    }

    private func taskContent(title: String, streak: Int) -> some View {
        VStack(spacing: 44) {
            Text("Задача\nвыполнена")
                .font(.sfProDisplay(96, weight: .bold))
                .foregroundStyle(theme.ink)
                .multilineTextAlignment(.center)
                .lineSpacing(2)

            Text(title)
                .font(.sfProDisplay(52, weight: .medium))
                .foregroundStyle(theme.ink.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineLimit(3)

            if streak > 0 {
                HStack(spacing: 14) {
                    Text("🔥").font(.system(size: 48))
                    Text("\(streak) подряд")
                        .font(.sfProDisplay(48, weight: .semibold))
                        .foregroundStyle(theme.ink)
                }
                .padding(.horizontal, 44)
                .padding(.vertical, 24)
                .background(theme.ink.opacity(0.12), in: Capsule())
            }
        }
        .padding(.horizontal, 100)
    }
}

// MARK: - Rendering

enum ShareCardRenderer {
    /// Renders a card to a native-resolution opaque image (1080x1920 story /
    /// 1080x1350 post).
    @MainActor
    static func render(_ kind: ShareCardKind,
                       name: String?,
                       theme: ShareCardTheme = .blue,
                       format: ShareCardFormat = .story) -> UIImage? {
        let card = ShareCardView(kind: kind, name: name, theme: theme, format: format)
        let renderer = ImageRenderer(content: card)
        renderer.scale = 1
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
    ScrollView(.horizontal) {
        HStack(spacing: 20) {
            ShareCardView(kind: .streak(days: 47, best: 60), name: "Арслан",
                          theme: .blue, format: .story)
                .scaleEffect(0.18).frame(width: 1080 * 0.18, height: 1920 * 0.18)
            ShareCardView(kind: .taskDone(title: "Пробежка 5 км", streak: 12), name: "Арслан",
                          theme: .light, format: .story)
                .scaleEffect(0.18).frame(width: 1080 * 0.18, height: 1920 * 0.18)
            ShareCardView(kind: .streak(days: 47, best: 60), name: "Арслан",
                          theme: .blue, format: .post)
                .scaleEffect(0.18).frame(width: 1080 * 0.18, height: 1350 * 0.18)
        }
        .padding()
    }
}
