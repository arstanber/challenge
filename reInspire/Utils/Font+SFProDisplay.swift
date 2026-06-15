import SwiftUI
import UIKit

extension Font {
    /// SF Pro Display at any point size. The plain `.system(size:)` font uses
    /// SF Pro Text below ~20pt and only switches to the Display optical variant
    /// for larger text; this forces the Display variant everywhere for a
    /// consistent display look on the home screen.
    static func sfProDisplay(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        Font(UIFont.sfProDisplay(ofSize: size, weight: weight.uiKit))
    }
}

extension UIFont {
    static func sfProDisplay(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        // Force the "Display" optical usage on the system font descriptor.
        // The UI-usage attribute alone overrides the weight back to regular,
        // so the weight trait is re-applied explicitly to keep semibold/bold
        // from rendering thin.
        let descriptor = base.fontDescriptor.addingAttributes([
            UIFontDescriptor.AttributeName(rawValue: "NSCTFontUIUsageAttribute"): "CTFontDisplayUsage",
            .traits: [UIFontDescriptor.TraitKey.weight: weight.rawValue]
        ])
        return UIFont(descriptor: descriptor, size: size)
    }
}

private extension Font.Weight {
    /// Map SwiftUI Font.Weight to the matching UIFont.Weight.
    var uiKit: UIFont.Weight {
        switch self {
        case .ultraLight: return .ultraLight
        case .thin:       return .thin
        case .light:      return .light
        case .medium:     return .medium
        case .semibold:   return .semibold
        case .bold:       return .bold
        case .heavy:      return .heavy
        case .black:      return .black
        default:          return .regular
        }
    }
}
