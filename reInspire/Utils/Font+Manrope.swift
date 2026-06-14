import SwiftUI

extension Font {
    static func manrope(_ weight: ManropeWeight = .regular, size: CGFloat) -> Font {
        .custom(weight.postScriptName, size: size)
    }
}

enum ManropeWeight {
    case regular, medium, semiBold, bold, extraBold

    var postScriptName: String {
        switch self {
        case .regular:   return "Manrope-Regular"
        case .medium:    return "Manrope-Medium"
        case .semiBold:  return "Manrope-SemiBold"
        case .bold:      return "Manrope-Bold"
        case .extraBold: return "Manrope-ExtraBold"
        }
    }
}
