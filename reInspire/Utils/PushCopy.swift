import Foundation

/// One push notification text. Pools live in `StandardCopy` (default tone)
/// and `ZoomerCopy` (zoomer mode); both are sampled at schedule time, so
/// the copy rotates on every re-schedule (app open, completion, toggle
/// flip), not on every delivery.
struct PushText {
    let title: String
    let body: String
}

/// Russian plural forms shared by the push-text pools.
enum RuPlural {
    /// "1 день" / "2 дня" / "5 дней".
    static func days(_ n: Int) -> String {
        "\(n) \(dayWord(n))"
    }

    /// "остался 1 день" / "осталось 2 дня" / "осталось 5 дней".
    static func remainingDays(_ n: Int) -> String {
        let verb = n % 10 == 1 && n % 100 != 11 ? "остался" : "осталось"
        return "\(verb) \(n) \(dayWord(n))"
    }

    private static func dayWord(_ n: Int) -> String {
        let mod10 = n % 10, mod100 = n % 100
        if mod10 == 1 && mod100 != 11 { return "день" }
        if (2...4).contains(mod10) && !(12...14).contains(mod100) { return "дня" }
        return "дней"
    }
}

/// English plural forms for the same dynamic push copy -- picked alongside
/// `RuPlural` based on `AppLanguage.current`, since these strings are built
/// from runtime data and can't go through the String Catalog like the
/// static pool entries do.
enum EnPlural {
    /// "1 day" / "5 days".
    static func days(_ n: Int) -> String {
        "\(n) day\(n == 1 ? "" : "s")"
    }

    /// "1 day to go" / "5 days to go".
    static func remainingDays(_ n: Int) -> String {
        "\(days(n)) to go"
    }
}
