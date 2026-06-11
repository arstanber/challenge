import SwiftUI

// MARK: - Bottom popup menu with 3 creation options

struct CreationMenuPopup: View {
    let onAIStepByStep: () -> Void
    let onBySaying: () -> Void
    let onByYourself: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider().background(Color(red: 0.79, green: 0.79, blue: 0.79))

            MenuRow(iconType: .aiSparkle, title: "AI step-by-step", action: onAIStepByStep)
            Divider().background(Color(red: 0.79, green: 0.79, blue: 0.79))

            MenuRow(iconType: .bySaying, title: "By saying", action: onBySaying)
            Divider().background(Color(red: 0.79, green: 0.79, blue: 0.79))

            MenuRow(iconType: .byYourself, title: "By yourself", action: onByYourself)
            Divider().background(Color(red: 0.79, green: 0.79, blue: 0.79))
        }
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 20, x: 0, y: -4)
    }
}

// MARK: - Menu icon types

enum MenuIconType {
    case aiSparkle, bySaying, byYourself
}

// MARK: - Menu Row

private struct MenuRow: View {
    let iconType: MenuIconType
    let title: String
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                GlassIconButton(iconType: iconType)

                Text(title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.black)
                    .lineLimit(1)

                Spacer()

                MenuPreviewImage(iconType: iconType)
            }
            .padding(.horizontal, 20)
            .frame(height: 80)
            .background(isPressed ? Color.gray.opacity(0.08) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.haptic)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isPressed = true }
                }
                .onEnded { _ in
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) { isPressed = false }
                }
        )
    }
}

// MARK: - Preview illustration per option

private struct MenuPreviewImage: View {
    let iconType: MenuIconType

    private var gradient: [Color] {
        switch iconType {
        case .aiSparkle:  return [Color(hex: "0048E2"), Color(hex: "8B5CF6")]
        case .bySaying:   return [Color(hex: "FF8A3D"), Color(hex: "FF4D4D")]
        case .byYourself: return [Color(hex: "18C29C"), Color(hex: "2FB873")]
        }
    }

    private var symbol: String {
        switch iconType {
        case .aiSparkle:  return "sparkles"
        case .bySaying:   return "waveform"
        case .byYourself: return "list.bullet.rectangle.fill"
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(LinearGradient(colors: gradient.map { $0.opacity(0.85) },
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
            .frame(width: 64, height: 48)
            .overlay(
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.06), lineWidth: 1)
            )
    }
}

// MARK: - Glass icon button

private struct GlassIconButton: View {
    let iconType: MenuIconType

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.97, green: 0.97, blue: 0.97))
                .frame(width: 53, height: 53)
                .overlay(Circle().fill(Color.white.opacity(0.65)))
                .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)

            iconContent
        }
        .frame(width: 53, height: 53)
    }

    @ViewBuilder
    private var iconContent: some View {
        switch iconType {
        case .aiSparkle:
            ZStack {
                SparkleShape(pointCount: 4, innerRatio: 0.4)
                    .fill(Color(red: 0.0, green: 0.282, blue: 0.886))
                    .frame(width: 10, height: 10)
                    .offset(x: -6, y: -6)
                SparkleShape(pointCount: 4, innerRatio: 0.35)
                    .fill(Color.black)
                    .frame(width: 22, height: 22)
                    .offset(x: 2, y: 2)
            }
        case .bySaying:
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(red: 0.0, green: 0.282, blue: 0.886))
                    .frame(width: 20, height: 4)
                    .offset(y: 9)
                Text("i")
                    .font(.system(size: 20, weight: .medium))
                    .italic()
                    .foregroundColor(.black)
                    .offset(y: -2)
                Circle()
                    .fill(Color(red: 0.0, green: 0.282, blue: 0.886))
                    .frame(width: 5, height: 5)
                    .offset(y: -13)
            }
        case .byYourself:
            ZStack {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(red: 0.0, green: 0.282, blue: 0.886))
                    .frame(width: 22, height: 4)
                    .offset(y: 9)
                Text("A")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.black)
                    .offset(y: -2)
            }
        }
    }
}

// MARK: - Sparkle shape

private struct SparkleShape: Shape {
    var pointCount: Int = 4
    var innerRatio: CGFloat = 0.35

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) / 2
        let innerRadius = outerRadius * innerRatio
        let angleStep = (2 * CGFloat.pi) / CGFloat(pointCount * 2)

        var path = Path()
        for i in 0..<(pointCount * 2) {
            let angle = CGFloat(i) * angleStep - CGFloat.pi / 2
            let radius = i.isMultiple(of: 2) ? outerRadius : innerRadius
            let point = CGPoint(
                x: center.x + radius * cos(angle),
                y: center.y + radius * sin(angle)
            )
            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        path.closeSubpath()
        return path
    }
}

#Preview {
    ZStack {
        Color.gray.opacity(0.1).ignoresSafeArea()
        VStack {
            Spacer()
            CreationMenuPopup(
                onAIStepByStep: {},
                onBySaying: {},
                onByYourself: {}
            )
            .padding(.horizontal, 12)
            .padding(.bottom, 100)
        }
    }
}
