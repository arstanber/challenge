import SwiftUI

/// The badge shown for a data connector: a full-bleed brand logo when one is
/// bundled (`DataConnector.logoAsset`), otherwise the tinted SF Symbol fallback
/// used by Telegram and the alarm clock.
struct ConnectorGlyph: View {
    let connector: DataConnector
    var size: CGFloat = 40
    var cornerRadius: CGFloat = 12
    /// Background opacity for the SF Symbol fallback tile.
    var fallbackFillOpacity: Double = 0.15

    var body: some View {
        if let asset = connector.logoAsset {
            Image(asset)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(connector.tint.opacity(fallbackFillOpacity))
                .frame(width: size, height: size)
                .overlay {
                    Image(systemName: connector.icon)
                        .font(.system(size: size * 0.45, weight: .medium))
                        .foregroundStyle(connector.tint)
                }
        }
    }
}
