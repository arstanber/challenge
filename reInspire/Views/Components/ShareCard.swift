import SwiftUI
import UIKit

// MARK: - Share card kind

/// What a share card depicts. Drives the body of `ShareCardView`.
enum ShareCardKind {
    /// The user's current global streak (with their best for context).
    case streak(days: Int, best: Int)
    /// A single task the user just completed. `connector` is the display name
    /// of the data source that auto-verified it (e.g. "Strava"), if any.
    case taskDone(title: String, streak: Int, connector: String? = nil)
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

    /// Opacity of the decorative burst. On blue the bright white burst is
    /// dialled back so it never washes out the white text it overlaps; on
    /// white the burst is already a faint ghost, so it stays full.
    var burstOpacity: Double {
        switch self {
        case .blue:  return 0.45
        case .light: return 1.0
        }
    }
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

    /// Burst image width (square art). Overflows the canvas and clips.
    var burstWidth: CGFloat {
        switch self {
        case .story: return 1500
        case .post:  return 1500
        }
    }

    /// Burst offset from the bottom-trailing corner (positive pushes the art
    /// off the bottom-right edge so the explosion origin sits in the corner).
    /// Offset from the bottom-leading corner (negative pushes the art off the
    /// bottom-left edge so the explosion origin sits in the corner).
    var burstOffset: CGSize {
        switch self {
        case .story: return CGSize(width: -550, height: 380)
        case .post:  return CGSize(width: -550, height: 360)
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
            // Burst-checkmark (decorative): explosion origin sits in the
            // bottom-left corner, spikes radiating up-right.
            .overlay(alignment: .bottomLeading) {
                Image("shareStar")
                    .resizable()
                    .scaledToFit()
                    .frame(width: format.burstWidth, height: format.burstWidth)
                    .opacity(theme.burstOpacity)
                    .offset(x: format.burstOffset.width, y: format.burstOffset.height)
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
            Text("@\(Constants.App.instagramHandle)")
                .font(.sfProDisplay(28, weight: .semibold))
                .foregroundStyle(theme.inkMuted)
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch kind {
        case let .streak(days, best):
            streakContent(days: days, best: best)
        case let .taskDone(title, streak, connector):
            taskContent(title: title, streak: streak, connector: connector)
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

    private func taskContent(title: String, streak: Int, connector: String?) -> some View {
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

            HStack(spacing: 16) {
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

                if let connector, !connector.isEmpty {
                    HStack(spacing: 12) {
                        Image(systemName: "bolt.horizontal.circle.fill")
                            .font(.system(size: 44))
                        Text(connector)
                            .font(.sfProDisplay(48, weight: .semibold))
                            .foregroundStyle(theme.ink)
                    }
                    .padding(.horizontal, 44)
                    .padding(.vertical, 24)
                    .background(theme.ink.opacity(0.12), in: Capsule())
                }
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
    /// Optional caption (with @mention + hashtags) attached for apps that
    /// accept share text (Telegram, WhatsApp, X). Instagram ignores it.
    var caption: String? = nil
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

// MARK: - Share composer

/// A request to share, wrapping the card content. Drives the composer sheet
/// via `.sheet(item:)`.
struct ShareRequest: Identifiable {
    let id = UUID()
    let kind: ShareCardKind
    var name: String?
}

/// In-app share screen: a live preview plus theme (blue/white) and format
/// (story/post) pickers, then a one-tap "Instagram Stories" or system-sheet
/// send. Presented as a sheet from the streak / verification screens.
struct ShareComposerView: View {
    let kind: ShareCardKind
    var name: String?

    @Environment(\.dismiss) private var dismiss
    @State private var theme: ShareCardTheme = .blue
    @State private var format: ShareCardFormat = .story
    @State private var sheetImage: ShareableImage?

    var body: some View {
        NavigationStack {
            VStack(spacing: 22) {
                preview

                VStack(spacing: 12) {
                    Picker("Тема", selection: $theme) {
                        Text("Синяя").tag(ShareCardTheme.blue)
                        Text("Белая").tag(ShareCardTheme.light)
                    }
                    .pickerStyle(.segmented)

                    Picker("Формат", selection: $format) {
                        Text("Сторис").tag(ShareCardFormat.story)
                        Text("Пост").tag(ShareCardFormat.post)
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 20)

                Spacer(minLength: 0)

                buttons
            }
            .padding(.top, 12)
            .padding(.bottom, 16)
            .navigationTitle("Поделиться")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Закрыть") { dismiss() }
                        .font(.sfProDisplay(16, weight: .semibold))
                }
            }
            .sheet(item: $sheetImage) { item in
                ShareCardSheet(items: item.caption.map { [item.image, $0] } ?? [item.image])
            }
        }
    }

    // MARK: Preview

    private var preview: some View {
        // Fixed preview width; the card scales to fit either aspect ratio.
        let previewWidth: CGFloat = 230
        let scale = previewWidth / format.size.width
        return ShareCardView(kind: kind, name: name, theme: theme, format: format)
            .frame(width: format.size.width, height: format.size.height)
            .scaleEffect(scale)
            .frame(width: format.size.width * scale, height: format.size.height * scale)
            .clipShape(RoundedRectangle(cornerRadius: 60 * scale, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 60 * scale, style: .continuous)
                .stroke(Color.primary.opacity(0.08)))
            .shadow(color: .black.opacity(0.12), radius: 16, y: 8)
            .animation(.easeInOut(duration: 0.2), value: theme)
            .animation(.easeInOut(duration: 0.2), value: format)
    }

    // MARK: Buttons

    private var buttons: some View {
        VStack(spacing: 10) {
            // Instagram Stories deep-links only into the Stories composer, so
            // it only makes sense for the story format. A feed post can only be
            // created via the system sheet (Instagram has no feed deep link).
            if format == .story {
                Button { share(toInstagram: true) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "camera.fill")
                        Text("Instagram Stories")
                    }
                    .font(.sfProDisplay(16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity).frame(height: 52)
                    .background(
                        LinearGradient(colors: [Color(hex: "C13584"), Color(hex: "F77737")],
                                       startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: 16)
                    )
                }
                .buttonStyle(.haptic)
            }

            Button { share(toInstagram: false) } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text(format == .post ? "Поделиться в ленте и др." : "Другие приложения")
                }
                .font(.sfProDisplay(16, weight: .semibold))
                .foregroundStyle(format == .post ? .white : Color.accentColor)
                .frame(maxWidth: .infinity).frame(height: 52)
                .background {
                    if format == .post {
                        RoundedRectangle(cornerRadius: 16).fill(Color.accentColor)
                    } else {
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.accentColor.opacity(0.5), lineWidth: 1.5)
                    }
                }
            }
            .buttonStyle(.haptic)
        }
        .padding(.horizontal, 20)
    }

    // MARK: Actions

    private var kindLabel: String {
        switch kind {
        case .streak:   return "streak"
        case .taskDone: return "task"
        }
    }

    /// Caption (with @mention + hashtags) for apps that accept share text.
    private var shareCaption: String {
        let tag = "@\(Constants.App.instagramHandle)"
        switch kind {
        case let .streak(days, _):
            return "🔥 \(days) дней подряд в reInspire! Присоединяйся: \(tag) #reInspire #привычки"
        case let .taskDone(title, _, _):
            return "Задача выполнена в reInspire ✅ \(title) \(tag) #reInspire #привычки"
        }
    }

    private func share(toInstagram: Bool) {
        Haptics.tap()
        guard let image = ShareCardRenderer.render(kind, name: name, theme: theme, format: format) else { return }
        AnalyticsService.shared.track(.shareCardShared, [
            "kind": kindLabel,
            "theme": theme == .blue ? "blue" : "light",
            "format": format == .story ? "story" : "post",
            "destination": toInstagram ? "instagram_stories" : "system_sheet"
        ])
        if toInstagram {
            InstagramStoryShare.share(image: image) { ok in
                if !ok { sheetImage = ShareableImage(image: image, caption: shareCaption) }
            }
        } else {
            sheetImage = ShareableImage(image: image, caption: shareCaption)
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
