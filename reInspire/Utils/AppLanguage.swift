import Foundation

/// Device-locale-derived app language. reInspire ships UI + server copy for
/// eleven languages (EN/RU/DE/KK/FR/AR/ES/JA/KO/PT/ZH-Hans) -- anything
/// else falls back to English.
/// No manual switcher; this mirrors how `users.timezone` is auto-synced from
/// the device, and the resolved code is stored in `users.language` so the
/// server can pick the language for server-composed pushes and AI responses
/// (keep aligned with supabase/functions/_shared/i18n.ts).
enum AppLanguage {
    /// Languages the app fully localizes. Keep aligned with the String
    /// Catalog, pbxproj `knownRegions`, and the server `Lang` union.
    static let supported: Set<String> = [
        "en", "ru", "de", "kk", "fr", "ar", "es", "ja", "ko", "pt", "zh-Hans",
    ]

    /// The active language code, restricted to `supported`.
    static var current: String {
        let preferred = Locale.preferredLanguages.first ?? "en"
        if preferred.lowercased().hasPrefix("zh") { return "zh-Hans" }
        let code = String(preferred.prefix(2)).lowercased()
        return supported.contains(code) ? code : "en"
    }

    /// Whether the active language is written right-to-left (Arabic).
    static var isRTL: Bool { current == "ar" }

    /// Pick a runtime-built string for the active language. These strings
    /// can't go through the String Catalog because they're assembled from
    /// runtime data (error messages, dynamic notification bodies, etc.).
    /// `en` is the fallback for any unmapped language.
    static func t(
        en: String,
        ru: String,
        de: String,
        kk: String,
        fr: String,
        ar: String,
        es: String? = nil,
        ja: String? = nil,
        ko: String? = nil,
        pt: String? = nil,
        zhHans: String? = nil
    ) -> String {
        switch current {
        case "ru": return ru
        case "de": return de
        case "kk": return kk
        case "fr": return fr
        case "ar": return ar
        case "es": return es ?? en
        case "ja": return ja ?? en
        case "ko": return ko ?? en
        case "pt": return pt ?? en
        case "zh-Hans": return zhHans ?? en
        default:   return en
        }
    }
}
