import SwiftUI
import UIKit

extension Color {
    /// Hex string ("RGB", "RRGGBB", or "AARRGGBB") to Color.
    init(hex: String) {
        let comps = Color.rgba(fromHex: hex)
        self.init(.sRGB, red: comps.r, green: comps.g, blue: comps.b, opacity: comps.a)
    }

    /// Light/dark adaptive color: resolves `hex` in light mode and `dark` in
    /// dark mode via a UIColor dynamic provider. Use for brand surfaces that
    /// need a hand-tuned dark variant rather than a system color.
    init(hex light: String, dark: String) {
        let l = Color.rgba(fromHex: light)
        let d = Color.rgba(fromHex: dark)
        self = Color(UIColor { trait in
            let c = trait.userInterfaceStyle == .dark ? d : l
            return UIColor(red: c.r, green: c.g, blue: c.b, alpha: c.a)
        })
    }

    private static func rgba(fromHex hex: String) -> (r: Double, g: Double, b: Double, a: Double) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: s).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch s.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        return (Double(r) / 255, Double(g) / 255, Double(b) / 255, Double(a) / 255)
    }
}
