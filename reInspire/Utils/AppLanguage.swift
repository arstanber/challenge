import Foundation

/// Device-locale-derived app language. EN/RU only -- anything that isn't
/// Russian is treated as English. No manual switcher; this mirrors how
/// `users.timezone` is auto-synced from the device.
enum AppLanguage {
    static var current: String {
        (Locale.preferredLanguages.first ?? "en").hasPrefix("ru") ? "ru" : "en"
    }
}
