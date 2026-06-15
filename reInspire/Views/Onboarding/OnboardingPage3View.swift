import SwiftUI

// MARK: - Page 3: Photo verification

struct ReInspirePhotoView: View {
    let onContinue: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottom) {

                // Fullscreen background photo
                Image("camera_preview")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geo.size.width, height: geo.size.height)
                    .clipped()

                // Dark gradient — bottom
                LinearGradient(
                    stops: [
                        .init(color: Color.black.opacity(0.0), location: 0.35),
                        .init(color: Color.black.opacity(0.88), location: 1.0)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                // Content
                VStack(alignment: .leading, spacing: 16) {
                    Text("reInspire.")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.black)
                        .lineSpacing(2)
                        .appearEffect(delay: 0.05)

                    Text("You can't talk yourself out of doing this. Send photo to prove.")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundColor(.white)
                        .lineSpacing(4)
                        .appearEffect(delay: 0.2)

                    Spacer()

                    LiquidGlassButton(title: "Continue", action: onContinue)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.bottom, OBStyle.ctaBottomPad)
                }
                .padding(.horizontal, 20)
                .padding(.top, 36)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .readableWidth(560)
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .ignoresSafeArea()
        }
        .ignoresSafeArea()
    }
}

#Preview {
    ReInspirePhotoView(onContinue: {})
}
