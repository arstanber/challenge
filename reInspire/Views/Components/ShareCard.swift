import SwiftUI
import UIKit

// MARK: - Share card kind

/// What a share card depicts. Drives the body of `ShareCardView`.
enum ShareCardKind {
    /// The user's current global streak (with their best for context).
    case streak(days: Int, best: Int)
    /// A single task the user just completed. `connector` is the data source
    /// that auto-verified it (e.g. Strava / Chess.com), if any -- its brand
    /// logo is stamped on the card.
    case taskDone(title: String, streak: Int, connector: DataConnector? = nil)
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
    /// Bake a still confetti scatter (used for the static-image fallback).
    var staticConfetti: Bool = false
    /// Overlay live, animated confetti (used for the composer preview only --
    /// never for the video base, which composites confetti per frame).
    var animatedConfetti: Bool = false
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
            // Confetti so the shared story/post looks celebratory.
            .overlay {
                if animatedConfetti {
                    AnimatedConfettiView(size: size)
                } else if staticConfetti {
                    StaticConfettiCanvas(size: size, time: 1.2)
                }
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

    private func taskContent(title: String, streak: Int, connector: DataConnector?) -> some View {
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

            // Stacked vertically so a streak chip and a connector chip never
            // collide / wrap when both are present.
            VStack(spacing: 16) {
                if streak > 0 {
                    HStack(spacing: 14) {
                        Text("🔥").font(.system(size: 48))
                        Text("\(streak) подряд")
                            .font(.sfProDisplay(48, weight: .semibold))
                            .foregroundStyle(theme.ink)
                            .fixedSize()
                    }
                    .padding(.horizontal, 44)
                    .padding(.vertical, 24)
                    .background(theme.ink.opacity(0.12), in: Capsule())
                }

                if let connector {
                    HStack(spacing: 16) {
                        ConnectorGlyph(connector: connector, size: 56, cornerRadius: 14)
                        Text(connector.displayName)
                            .font(.sfProDisplay(48, weight: .semibold))
                            .foregroundStyle(theme.ink)
                            .fixedSize()
                    }
                    .padding(.horizontal, 40)
                    .padding(.vertical, 20)
                    .background(theme.ink.opacity(0.12), in: Capsule())
                }
            }
        }
        .padding(.horizontal, 80)
    }
}

// MARK: - Confetti model (shared by preview + video)

/// Deterministic falling-confetti field. The same specs drive the live preview
/// (`AnimatedConfettiView`), the static fallback (`StaticConfettiCanvas`) and
/// the per-frame video compositor, so all three look identical.
enum ShareConfetti {
    /// Colours that pop on both the blue and white backgrounds.
    static let palette: [Color] = [
        Color(hex: "FFC542"), Color(hex: "FF6B6B"),
        Color(hex: "2FB873"), Color(hex: "B388FF"), Color(hex: "FF7A18")
    ]
    /// UIColor mirror for the Core Graphics video path.
    static let uiPalette: [UIColor] = [
        UIColor(red: 1.00, green: 0.77, blue: 0.26, alpha: 1),
        UIColor(red: 1.00, green: 0.42, blue: 0.42, alpha: 1),
        UIColor(red: 0.18, green: 0.72, blue: 0.45, alpha: 1),
        UIColor(red: 0.70, green: 0.53, blue: 1.00, alpha: 1),
        UIColor(red: 1.00, green: 0.48, blue: 0.09, alpha: 1)
    ]

    struct Spec {
        let x0: CGFloat        // 0..1 horizontal anchor
        let y0: CGFloat        // 0..1 vertical phase
        let colorIndex: Int
        let w: CGFloat         // piece width (px)
        let fall: CGFloat      // heights per second
        let drift: CGFloat     // horizontal sway amplitude (fraction of width)
        let rot: Double        // rotations per second
        let phase: CGFloat     // 0..1
    }

    static func specs(count: Int = 90) -> [Spec] {
        (0..<count).map { i in
            let r1 = frac(sin(Double(i) * 12.9898) * 43758.5453)
            let r2 = frac(sin(Double(i) * 78.2330) * 12345.6789)
            let r3 = frac(sin(Double(i) * 39.4250) * 9876.54321)
            let r4 = frac(cos(Double(i) * 21.7100) * 5555.55555)
            let r5 = frac(sin(Double(i) * 53.1700) * 2468.13579)
            return Spec(
                x0: r1,
                y0: r2,
                colorIndex: i % palette.count,
                w: 14 + r3 * 18,
                fall: 0.16 + r4 * 0.22,
                drift: 0.015 + r5 * 0.04,
                rot: 0.4 + r3 * 1.2,
                phase: r4
            )
        }
    }

    /// Position / rotation / size of a piece at time `t` (seconds) in `size`.
    static func frame(_ s: Spec, t: Double, size: CGSize) -> (pos: CGPoint, angle: CGFloat, w: CGFloat, h: CGFloat) {
        let span: CGFloat = 1.6
        var y = (s.y0 + s.fall * CGFloat(t)).truncatingRemainder(dividingBy: span)
        if y < 0 { y += span }
        y -= 0.3                                  // start a little above the top
        let x = s.x0 * size.width + s.drift * size.width * CGFloat(sin(t * 1.6 + Double(s.phase) * 6.28))
        let angle = CGFloat(s.rot * t * 2 * .pi + Double(s.phase) * 6.28)
        return (CGPoint(x: x, y: y * size.height), angle, s.w, s.w * 1.7)
    }

    /// Fractional part, used as a cheap seeded PRNG.
    static func frac(_ v: Double) -> Double { v - v.rounded(.down) }
}

/// Static confetti scatter at a fixed time (for the image fallback).
private struct StaticConfettiCanvas: View {
    let size: CGSize
    var time: Double = 1.2
    private let specs = ShareConfetti.specs()

    var body: some View {
        Canvas { ctx, _ in
            for s in specs {
                let f = ShareConfetti.frame(s, t: time, size: size)
                draw(f, color: ShareConfetti.palette[s.colorIndex], in: &ctx)
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
    }

    private func draw(_ f: (pos: CGPoint, angle: CGFloat, w: CGFloat, h: CGFloat),
                      color: Color, in ctx: inout GraphicsContext) {
        var p = Path(roundedRect: CGRect(x: -f.w / 2, y: -f.h / 2, width: f.w, height: f.h), cornerRadius: 4)
        p = p.applying(.init(rotationAngle: f.angle))
        p = p.applying(.init(translationX: f.pos.x, y: f.pos.y))
        ctx.opacity = 0.95
        ctx.fill(p, with: .color(color))
    }
}

/// Live animated confetti for the composer preview.
private struct AnimatedConfettiView: View {
    let size: CGSize
    private let specs = ShareConfetti.specs()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { ctx, _ in
                let t = timeline.date.timeIntervalSinceReferenceDate
                    .truncatingRemainder(dividingBy: 1000)
                for s in specs {
                    let f = ShareConfetti.frame(s, t: t, size: size)
                    var p = Path(roundedRect: CGRect(x: -f.w / 2, y: -f.h / 2, width: f.w, height: f.h),
                                 cornerRadius: 4)
                    p = p.applying(.init(rotationAngle: f.angle))
                    p = p.applying(.init(translationX: f.pos.x, y: f.pos.y))
                    ctx.opacity = 0.95
                    ctx.fill(p, with: .color(ShareConfetti.palette[s.colorIndex]))
                }
            }
        }
        .frame(width: size.width, height: size.height)
        .allowsHitTesting(false)
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
                       format: ShareCardFormat = .story,
                       staticConfetti: Bool = false) -> UIImage? {
        let card = ShareCardView(kind: kind, name: name, theme: theme, format: format,
                                 staticConfetti: staticConfetti)
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

    /// Opens Instagram Stories with `videoURL` as the story background video.
    @MainActor
    static func shareVideo(url videoURL: URL, completion: @escaping @MainActor @Sendable (Bool) -> Void) {
        let appID = Bundle.main.bundleIdentifier ?? "com.reinspire"
        guard let url = URL(string: "instagram-stories://share?source_application=\(appID)"),
              let data = try? Data(contentsOf: videoURL) else {
            completion(false)
            return
        }
        let items: [[String: Any]] = [[
            "com.instagram.sharedSticker.backgroundVideo": data
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

/// A rendered video file awaiting a share destination (system sheet).
struct ShareableFile: Identifiable {
    let id = UUID()
    let url: URL
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
    @State private var shareFile: ShareableFile?
    @State private var confettiTrigger = 0
    @State private var isRendering = false

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
            .sheet(item: $shareFile) { file in
                ShareCardSheet(items: file.caption.map { [file.url, $0] } ?? [file.url])
            }
            .overlay {
                ConfettiView(trigger: confettiTrigger)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            .overlay {
                if isRendering { renderingOverlay }
            }
        }
    }

    private var renderingOverlay: some View {
        ZStack {
            Color.black.opacity(0.25).ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView().tint(.white)
                Text("Готовим видео…")
                    .font(.sfProDisplay(14, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .padding(24)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
        .transition(.opacity)
    }

    // MARK: Preview

    private var preview: some View {
        // Fixed preview width; the card scales to fit either aspect ratio.
        let previewWidth: CGFloat = 230
        let scale = previewWidth / format.size.width
        return ShareCardView(kind: kind, name: name, theme: theme, format: format,
                             animatedConfetti: true)
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
                .disabled(isRendering)
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
            .disabled(isRendering)
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
        guard !isRendering else { return }
        Haptics.success()
        confettiTrigger += 1
        AnalyticsService.shared.track(.shareCardShared, [
            "kind": kindLabel,
            "theme": theme == .blue ? "blue" : "light",
            "format": format == .story ? "story" : "post",
            "destination": toInstagram ? "instagram_stories" : "system_sheet"
        ])

        // Render the base card (no confetti) on the main actor, then encode an
        // animated-confetti video off-main. Fall back to a static image if the
        // video export fails.
        guard let base = ShareCardRenderer.render(kind, name: name, theme: theme, format: format),
              let baseData = base.pngData() else { return }
        let size = format.size
        let caption = shareCaption
        withAnimation { isRendering = true }

        Task {
            let videoURL = await ShareVideoRenderer.render(baseData: baseData, size: size)
            await MainActor.run {
                withAnimation { isRendering = false }
                if let videoURL {
                    if toInstagram {
                        InstagramStoryShare.shareVideo(url: videoURL) { ok in
                            if !ok { shareFile = ShareableFile(url: videoURL, caption: caption) }
                        }
                    } else {
                        shareFile = ShareableFile(url: videoURL, caption: caption)
                    }
                } else {
                    // Static-image fallback.
                    let image = ShareCardRenderer.render(kind, name: name, theme: theme,
                                                         format: format, staticConfetti: true) ?? base
                    if toInstagram {
                        InstagramStoryShare.share(image: image) { ok in
                            if !ok { sheetImage = ShareableImage(image: image, caption: caption) }
                        }
                    } else {
                        sheetImage = ShareableImage(image: image, caption: caption)
                    }
                }
            }
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
