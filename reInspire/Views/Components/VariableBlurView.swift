import SwiftUI
import UIKit

// MARK: - Progressive (variable) blur
// Blur radius ramps from 0 at the top edge to `maxBlurRadius` at the bottom,
// with no material tint -- content underneath keeps its own colors and just
// goes increasingly out of focus, like the system home-screen dock blur.

struct VariableBlurView: UIViewRepresentable {
    var maxBlurRadius: CGFloat = 16

    func makeUIView(context: Context) -> VariableBlurUIView {
        VariableBlurUIView(maxBlurRadius: maxBlurRadius)
    }

    func updateUIView(_ uiView: VariableBlurUIView, context: Context) {}
}

final class VariableBlurUIView: UIVisualEffectView {
    init(maxBlurRadius: CGFloat) {
        super.init(effect: UIBlurEffect(style: .regular))

        // CAFilter(type: "variableBlur") scales the blur radius per-pixel by
        // the alpha of the mask image: transparent = sharp, opaque = full blur.
        let selector = NSSelectorFromString("filterWithType:")
        guard
            let filterClass = NSClassFromString("CAFilter") as? NSObject.Type,
            filterClass.responds(to: selector),
            let variableBlur = filterClass.perform(selector, with: "variableBlur")?
                .takeUnretainedValue() as? NSObject,
            let mask = Self.gradientMask()
        else { return }

        variableBlur.setValue(maxBlurRadius, forKey: "inputRadius")
        variableBlur.setValue(mask, forKey: "inputMaskImage")
        variableBlur.setValue(true, forKey: "inputNormalizeEdges")

        // The first subview hosts the backdrop layer that samples content
        // behind the view; the remaining subviews paint the material tint --
        // hide them so the result is pure blur with no gray wash.
        subviews.first?.layer.filters = [variableBlur]
        for tintView in subviews.dropFirst() { tintView.alpha = 0 }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        guard let window, let backdropLayer = subviews.first?.layer else { return }
        backdropLayer.setValue(window.screen.scale, forKey: "scale")
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        // Deliberately empty: the superclass resets the backdrop filters here.
    }

    /// Vertical alpha ramp: transparent (sharp) at the top, opaque (max blur)
    /// at the bottom.
    private static func gradientMask() -> CGImage? {
        let size = CGSize(width: 1, height: 128)
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            guard let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [
                    UIColor.black.withAlphaComponent(0).cgColor,
                    UIColor.black.cgColor,
                ] as CFArray,
                locations: [0, 1]
            ) else { return }
            ctx.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: 0, y: size.height),
                options: [.drawsAfterEndLocation]
            )
        }
        return image.cgImage
    }
}
