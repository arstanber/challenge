import SwiftUI
import os.log

/// PRO feature: switch between the bundled alternate app icons
/// (asset catalog sets listed in ASSETCATALOG_COMPILER_ALTERNATE_APPICON_NAMES).
struct AppIconPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var current = UIApplication.shared.alternateIconName
    @State private var errorMessage: String?

    private let logger = Logger(subsystem: "com.reinspire", category: "AppIconPickerView")

    /// nil iconName = the primary icon.
    private let options: [(iconName: String?, preview: String, title: String)] = [
        (nil,             "icon_preview_blue",   String(localized: "Синий")),
        ("AppIconDark",   "icon_preview_dark",   String(localized: "Тёмный")),
        ("AppIconViolet", "icon_preview_violet", String(localized: "Фиолетовый")),
        ("AppIconOrange", "icon_preview_orange", String(localized: "Оранжевый")),
        ("AppIconGreen",  "icon_preview_green",  String(localized: "Зелёный")),
    ]

    var body: some View {
        ZStack(alignment: .top) {
            Color(.systemBackground).ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3),
                          spacing: 22) {
                    ForEach(options, id: \.preview) { option in
                        iconCell(option)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 80)
                .padding(.bottom, 40)
            }

            header
        }
        .alert("Ошибка", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("ОК") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        ZStack {
            Text("Значок приложения")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.primary)
            HStack {
                Spacer()
                Button { Haptics.tap(); dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(Color.primary.opacity(0.1)))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .background(.ultraThinMaterial)
    }

    private func iconCell(_ option: (iconName: String?, preview: String, title: String)) -> some View {
        let selected = current == option.iconName
        return Button {
            select(option.iconName)
        } label: {
            VStack(spacing: 8) {
                Image(option.preview)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 68, height: 68)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(selected ? Color(hex: "0A84FF") : Color.primary.opacity(0.08),
                                          lineWidth: selected ? 3 : 1)
                    )
                HStack(spacing: 4) {
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundStyle(Color(hex: "0A84FF"))
                    }
                    Text(option.title)
                        .font(.manrope(selected ? .bold : .medium, size: 13))
                        .foregroundColor(selected ? .primary : .primary.opacity(0.55))
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func select(_ name: String?) {
        guard name != current else { return }
        Haptics.selection()
        Task {
            do {
                try await UIApplication.shared.setAlternateIconName(name)
                current = name
                Haptics.success()
            } catch {
                logger.error("setAlternateIconName failed: \(error.localizedDescription)")
                errorMessage = String(localized: "Не удалось сменить значок. Попробуйте ещё раз.")
            }
        }
    }
}

#Preview {
    AppIconPickerView()
}
