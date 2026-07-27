import Foundation

/// Central read access to the preferences SettingsView stores in UserDefaults.
/// Raw values are the exact option strings shown in the settings menus --
/// keep them in sync with SettingsView's `options:` arrays.
enum AppPrefs {
    enum Key {
        static let timeFormat = "timeFormat"
        static let units = "units"
        static let weekStart = "weekStart"
        static let groupCompleted = "groupCompleted"
        static let strictMode = "strictMode"
        static let zoomerMode = "zoomerMode"
        static let liveActivityEnabled = "liveActivityEnabled"
        static let lastSeenWhatsNewVersion = "lastSeenWhatsNewVersion"
        static let dismissedHomePremiumVersion = "dismissedHomePremiumVersion"
    }

    enum Option {
        static let h24 = "24 часа"
        static let h12 = "12 часов"
        static let metric = "Метр. (км, мл)"
        static let imperial = "Имп. (мили)"
        static let monday = "Понедельник"
        static let sunday = "Воскресенье"
    }

    private static var defaults: UserDefaults { .standard }

    static var is24Hour: Bool { defaults.string(forKey: Key.timeFormat) != Option.h12 }
    static var isMetric: Bool { defaults.string(forKey: Key.units) != Option.imperial }
    static var weekStartsMonday: Bool { defaults.string(forKey: Key.weekStart) != Option.sunday }
    static var groupCompleted: Bool { (defaults.object(forKey: Key.groupCompleted) as? Bool) ?? true }
    static var strictMode: Bool { (defaults.object(forKey: Key.strictMode) as? Bool) ?? true }
    /// Gen-Z tone for push notifications and nudges. Off by default.
    static var zoomerMode: Bool { (defaults.object(forKey: Key.zoomerMode) as? Bool) ?? false }
    /// Live Activity / Dynamic Island progress banner. On by default; turning
    /// it off ends any running activity and suppresses new launches.
    static var liveActivityEnabled: Bool { (defaults.object(forKey: Key.liveActivityEnabled) as? Bool) ?? true }

    /// Calendar honoring "Начало недели".
    static var calendar: Calendar {
        var c = Calendar.current
        c.firstWeekday = weekStartsMonday ? 2 : 1
        return c
    }

    /// ISO weekdays (1=Mon..7=Sun) in the user's preferred display order.
    static var orderedIsoWeekdays: [Int] {
        weekStartsMonday ? [1, 2, 3, 4, 5, 6, 7] : [7, 1, 2, 3, 4, 5, 6]
    }

    /// Short Russian weekday labels indexed by ISO weekday - 1 (Mon..Sun).
    static let isoWeekdayShortLabels = ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]

    /// Weekday header labels ordered by the week-start setting.
    static var orderedWeekdayLabels: [String] {
        orderedIsoWeekdays.map { isoWeekdayShortLabels[$0 - 1] }
    }

    /// Locale honoring "Формат времени" -- drives 12/24h in DatePickers and
    /// `.formatted()` output when injected via `.environment(\.locale, _)`.
    static var locale: Locale {
        var comps = Locale.Components(locale: .current)
        comps.hourCycle = is24Hour ? .zeroToTwentyThree : .oneToTwelve
        return Locale(components: comps)
    }

    // MARK: - Units

    static let kmPerMile = 1.609344

    /// Distance in the display unit: km as-is, miles when imperial.
    static func displayDistance(_ km: Double) -> Double {
        isMetric ? km : km / kmPerMile
    }

    static var distanceUnit: String { isMetric ? "км" : "миль" }
}
