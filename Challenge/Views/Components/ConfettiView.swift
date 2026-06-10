import SwiftUI

// MARK: - Confetti burst

/// Lightweight confetti. Fires once when `trigger` changes.
struct ConfettiView: View {
    let trigger: Int
    var pieceCount: Int = 80

    @State private var pieces: [ConfettiPiece] = []

    private let palette: [Color] = [
        Color(red: 0.0, green: 0.282, blue: 0.886),  // app blue
        Color(hex: "0048E2"),
        Color(hex: "FFC542"),
        Color(hex: "FF6B6B"),
        Color(hex: "5AD8A6"),
        Color(hex: "B388FF")
    ]

    var body: some View {
        GeometryReader { geo in
            ZStack {
                ForEach(pieces) { piece in
                    ConfettiPieceView(piece: piece)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .onChange(of: trigger) { _, _ in
                burst(in: geo.size)
            }
        }
        .allowsHitTesting(false)
    }

    private func burst(in size: CGSize) {
        pieces = (0..<pieceCount).map { _ in
            ConfettiPiece(
                startX: CGFloat.random(in: 0...size.width),
                color: palette.randomElement()!,
                size: CGFloat.random(in: 6...12),
                rotation: Double.random(in: 0...360),
                duration: Double.random(in: 1.8...3.0),
                horizontalDrift: CGFloat.random(in: -60...60),
                screenHeight: size.height
            )
        }
        // Clear after the longest animation finishes
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.2) {
            pieces = []
        }
    }
}

struct ConfettiPiece: Identifiable {
    let id = UUID()
    let startX: CGFloat
    let color: Color
    let size: CGFloat
    let rotation: Double
    let duration: Double
    let horizontalDrift: CGFloat
    let screenHeight: CGFloat
}

private struct ConfettiPieceView: View {
    let piece: ConfettiPiece
    @State private var animate = false

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(piece.color)
            .frame(width: piece.size, height: piece.size * 0.6)
            .rotationEffect(.degrees(animate ? piece.rotation + 360 : piece.rotation))
            .position(
                x: piece.startX + (animate ? piece.horizontalDrift : 0),
                y: animate ? piece.screenHeight + 40 : -40
            )
            .opacity(animate ? 0 : 1)
            .onAppear {
                withAnimation(.easeIn(duration: piece.duration)) {
                    animate = true
                }
            }
    }
}
