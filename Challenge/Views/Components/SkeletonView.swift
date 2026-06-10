import SwiftUI

// MARK: - Shimmer modifier

struct Shimmer: ViewModifier {
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(0.55),
                            Color.white.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 0.6)
                    .offset(x: phase * geo.size.width * 1.6)
                }
                .blendMode(.plusLighter)
            )
            .mask(content)
            .onAppear {
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1
                }
            }
    }
}

extension View {
    func shimmering() -> some View { modifier(Shimmer()) }
}

// MARK: - Skeleton task list

struct SkeletonTaskList: View {
    var rows: Int = 5

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { i in
                SkeletonTaskRow(widthFraction: [0.7, 0.5, 0.85, 0.6, 0.75][i % 5])
            }
        }
        .shimmering()
    }
}

private struct SkeletonTaskRow: View {
    let widthFraction: CGFloat
    private let base = Color.black.opacity(0.07)

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(base)
                    .frame(width: 24, height: 24)

                VStack(alignment: .leading, spacing: 10) {
                    GeometryReader { geo in
                        RoundedRectangle(cornerRadius: 5)
                            .fill(base)
                            .frame(width: geo.size.width * widthFraction, height: 17)
                    }
                    .frame(height: 17)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(base)
                        .frame(width: 60, height: 18)
                }
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 20)

            Rectangle()
                .fill(Color.black.opacity(0.06))
                .frame(height: 1)
        }
    }
}
