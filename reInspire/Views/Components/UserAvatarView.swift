import SwiftUI

/// Circular user avatar: shows the uploaded photo when present, otherwise a
/// colored circle with the first letter of the user's name/email. Reused by the
/// settings profile card, the family member list, and anywhere a face is shown.
struct UserAvatarView: View {
    let urlString: String?
    let label: String
    var size: CGFloat = 44
    var tint: Color = .orange

    var body: some View {
        if let urlString, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().scaledToFill()
                } else {
                    initial
                }
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
        } else {
            initial.frame(width: size, height: size)
        }
    }

    private var initial: some View {
        Circle()
            .fill(tint.gradient)
            .overlay {
                Text(String(label.prefix(1)).uppercased())
                    .font(.system(size: size * 0.42, weight: .bold))
                    .foregroundStyle(.white)
            }
    }
}
