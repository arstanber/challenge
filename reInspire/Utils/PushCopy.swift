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

/// German plural forms ("1 Tag" / "5 Tage").
enum DePlural {
    static func days(_ n: Int) -> String {
        "\(n) Tag\(n == 1 ? "" : "e")"
    }

    /// "noch 1 Tag" / "noch 5 Tage".
    static func remainingDays(_ n: Int) -> String {
        "noch \(days(n))"
    }
}

/// Kazakh plural forms. Counted nouns stay in the singular form ("1 күн" /
/// "5 күн"), so the word never changes -- only the number does.
enum KkPlural {
    static func days(_ n: Int) -> String {
        "\(n) күн"
    }

    /// "1 күн қалды" / "5 күн қалды".
    static func remainingDays(_ n: Int) -> String {
        "\(days(n)) қалды"
    }
}

/// French plural forms ("1 jour" / "5 jours").
enum FrPlural {
    static func days(_ n: Int) -> String {
        "\(n) jour\(n == 1 ? "" : "s")"
    }

    /// "encore 1 jour" / "encore 5 jours".
    static func remainingDays(_ n: Int) -> String {
        "encore \(days(n))"
    }
}

/// Arabic plural forms. Arabic counts in singular/dual/paucal/plural; this
/// covers the common cases: 1 ("يوم واحد"), 2 ("يومان"), 3-10 ("{n} أيام"),
/// 11+ ("{n} يومًا").
enum ArPlural {
    static func days(_ n: Int) -> String {
        switch n {
        case 1:      return "يوم واحد"
        case 2:      return "يومان"
        case 3...10: return "\(n) أيام"
        default:     return "\(n) يومًا"
        }
    }

    /// "بقي يوم واحد" / "بقيت 5 أيام".
    static func remainingDays(_ n: Int) -> String {
        let verb = (n == 1 || n > 10) ? "بقي" : "بقيت"
        return "\(verb) \(days(n))"
    }
}

/// Unified plural picker -- routes to the right language's forms based on
/// `AppLanguage.current`, so callers don't branch by hand.
enum Plural {
    static func days(_ n: Int) -> String {
        switch AppLanguage.current {
        case "ru": return RuPlural.days(n)
        case "de": return DePlural.days(n)
        case "kk": return KkPlural.days(n)
        case "fr": return FrPlural.days(n)
        case "ar": return ArPlural.days(n)
        default:   return EnPlural.days(n)
        }
    }

    static func remainingDays(_ n: Int) -> String {
        switch AppLanguage.current {
        case "ru": return RuPlural.remainingDays(n)
        case "de": return DePlural.remainingDays(n)
        case "kk": return KkPlural.remainingDays(n)
        case "fr": return FrPlural.remainingDays(n)
        case "ar": return ArPlural.remainingDays(n)
        default:   return EnPlural.remainingDays(n)
        }
    }
}
