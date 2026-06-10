import SwiftUI

// MARK: - Task category

struct TaskCategory: Hashable {
    let label: String
    let hue: Double
    let saturation: Double
    let brightness: Double

    init(label: String, hue: Double, saturation: Double = 0.68, brightness: Double = 0.90) {
        self.label    = label
        self.hue        = hue
        self.saturation = saturation
        self.brightness = brightness
    }

    var color: Color { Color(hue: hue, saturation: saturation, brightness: brightness) }

    func hash(into hasher: inout Hasher) { hasher.combine(label) }
    static func == (lhs: TaskCategory, rhs: TaskCategory) -> Bool { lhs.label == rhs.label }
}

// MARK: - Categorizer

enum TaskCategorizer {

    // All colors live in the 4580FF blue family (hue 0.54–0.78).
    // Saturation + brightness vary to keep each shade distinct.
    // Hues are kept in the 0.54–0.68 window (blue → periwinkle, never violet).
    // Saturation & brightness vary to give each shade a distinct personality.
    private static let buckets: [(label: String, hue: Double, sat: Double, bri: Double, keywords: [String])] = [

        ("SPORT", 0.60, 0.85, 0.86, [
            "run", "running", "jog", "jogging", "gym", "workout", "exercise", "sport", "sports",
            "cycling", "bike", "bicycle", "swim", "swimming", "football", "soccer", "basketball",
            "tennis", "lift", "lifting", "pushup", "push-up", "squat", "cardio", "yoga", "pilates",
            "stretch", "hike", "hiking", "walk", "walking", "dance", "dancing", "crossfit",
            "boxing", "climbing", "volleyball", "baseball", "hockey", "golf", "skateboard",
            "snowboard", "ski", "skiing", "rowing", "sprint", "marathon", "training", "weights",
            "fitness", "active", "muscle", "abs", "plank",
            "бег", "пробеж", "бегать", "спорт", "трениров", "зал", "отжим", "присед",
            "велосипед", "плав", "футбол", "баскетбол", "теннис", "качалка", "фитнес",
            "йога", "растяжка", "поход", "прогулк", "танц", "бокс", "скалолаз", "лыж",
            "кардио", "мышц", "атлет", "силов"
        ]),

        ("WELLNESS", 0.56, 0.55, 0.90, [
            "water", "hydrate", "hydration", "drink", "sleep", "vitamin", "doctor", "dentist",
            "medicine", "rest", "nap", "health", "healthy", "supplement", "medication", "pill",
            "appointment", "checkup", "blood pressure", "flu", "cold", "sick", "recover",
            "wellness", "wellbeing", "physical", "body", "weight loss", "detox", "immune",
            "вода", "сон", "спать", "витамин", "врач", "здоров", "отдых", "лекарств",
            "таблетк", "аптека", "давление", "прием", "обследован", "похудет", "вес",
            "белок", "иммунитет", "детокс"
        ]),

        ("FOOD", 0.58, 0.42, 0.95, [
            "eat", "meal", "breakfast", "lunch", "dinner", "cook", "cooking", "groceries",
            "grocery", "food", "recipe", "bake", "baking", "restaurant", "snack", "fruit",
            "vegetable", "meat", "fish", "salad", "soup", "pizza", "burger", "cafe", "coffee",
            "tea", "hungry", "hunger", "nutrition", "calorie", "protein", "diet", "menu",
            "еда", "завтрак", "обед", "ужин", "готов", "продукты", "покупки", "рецепт",
            "кухня", "ресторан", "кафе", "перекус", "голод", "фрукт", "овощ", "мясо",
            "рыба", "салат", "суп", "кофе", "чай", "питани"
        ]),

        ("LEARN", 0.65, 0.72, 0.88, [
            "study", "learn", "learning", "read", "book", "homework", "course", "lecture",
            "exam", "test", "revise", "language", "research", "notes", "class", "school",
            "college", "university", "tutor", "assignment", "essay", "degree", "certificate",
            "skill", "knowledge", "practice", "coding", "programming", "math", "science",
            "history", "write", "article", "chapter",
            "учеб", "учить", "читать", "книг", "урок", "экзамен", "курс", "язык",
            "домашн", "задани", "школ", "университет", "лекци", "конспект", "диплом",
            "навык", "изучать", "понять", "програм", "математик"
        ]),

        ("WORK", 0.63, 0.88, 0.84, [
            "work", "email", "report", "meeting", "project", "client", "deadline",
            "presentation", "pdf", "code", "ticket", "call", "zoom", "slack", "task",
            "boss", "office", "remote", "salary", "promotion", "interview", "hire", "career",
            "business", "startup", "launch", "deploy", "develop", "design", "review",
            "feedback", "budget", "proposal", "contract", "invoice", "strategy", "pipeline",
            "работ", "почт", "отчет", "встреч", "проект", "клиент", "созвон",
            "презентац", "офис", "удален", "зарплат", "карьер", "начальник", "бизнес",
            "программ", "разработк", "дизайн", "дедлайн", "стратег"
        ]),

        ("MONEY", 0.62, 0.70, 0.78, [
            "pay", "bill", "budget", "money", "invoice", "tax", "bank", "save", "invest",
            "investment", "loan", "credit", "debt", "insurance", "wallet", "payment",
            "transfer", "rent", "mortgage", "expense", "income", "finance", "stock", "crypto",
            "subscription", "subscribe", "spend", "purchase", "buy", "sell", "cost", "price",
            "оплат", "счет", "бюджет", "деньг", "налог", "банк", "накоп", "долг",
            "кредит", "страховк", "перевод", "аренда", "расход", "доход", "инвестиц",
            "крипто", "куп", "продат", "цена", "стоим"
        ]),

        ("HOME", 0.59, 0.40, 0.94, [
            "clean", "cleaning", "laundry", "dishes", "tidy", "vacuum", "trash", "garbage",
            "garden", "gardening", "repair", "fix", "chores", "organize", "declutter",
            "wash", "paint", "move", "furniture", "decorate", "plant", "water plant",
            "pet", "dog", "cat", "maintenance", "plumbing", "electricity", "shopping",
            "убор", "стирк", "посуд", "мусор", "ремонт", "сад", "дом", "квартир",
            "полив", "питомец", "кошк", "собак", "порядок", "мыть", "чисти",
            "мебел", "переезд", "декор"
        ]),

        ("MIND", 0.67, 0.50, 0.92, [
            "meditate", "meditation", "journal", "journaling", "gratitude", "breathe",
            "breathing", "mindful", "mindfulness", "relax", "relaxation", "therapy",
            "therapist", "anxiety", "stress", "mood", "mental", "calm", "peace", "reflect",
            "self-care", "self care", "affirmation", "grateful", "happy", "joy", "emotion",
            "confidence", "motivation", "mindset", "thoughts", "feelings", "wellbeing",
            "медитац", "дневник", "благодарн", "дыхан", "релакс", "терап", "стресс",
            "тревог", "настроен", "спокойств", "счасть", "эмоци", "позитив",
            "мотивац", "уверенн", "мышлен", "психолог"
        ]),

        ("SOCIAL", 0.54, 0.65, 0.88, [
            "call", "message", "text", "meet", "friend", "family", "party", "date",
            "dinner", "event", "hangout", "chat", "community", "volunteer", "gift",
            "birthday", "anniversary", "wedding", "reunion", "network", "connect",
            "relationship", "love", "mom", "dad", "parent", "brother", "sister",
            "colleague", "group", "club", "team",
            "друз", "семь", "позвонит", "встрет", "родител", "праздник",
            "день рождения", "свидани", "подарок", "общен", "знаком",
            "написат", "сообщ", "команд", "вечеринк", "мама", "папа"
        ]),
    ]

    private static let fallback = TaskCategory(label: "LIFE", hue: 0.64, saturation: 0.35, brightness: 0.88)

    // MARK: - Public API

    static func category(for title: String) -> TaskCategory {
        let t = title.lowercased()
        for b in buckets where b.keywords.contains(where: { t.contains($0) }) {
            return TaskCategory(label: b.label, hue: b.hue, saturation: b.sat, brightness: b.bri)
        }
        return fallback
    }

    /// Prefer the Gemini-assigned category stored on the activity; fall back to keywords.
    static func category(for activity: Activity) -> TaskCategory {
        if let stored = activity.category, !stored.isEmpty {
            return category(forLabel: stored)
        }
        return category(for: activity.title)
    }

    /// Look up a category by its exact label string (used when Gemini returns a label).
    static func category(forLabel label: String) -> TaskCategory {
        // Map Gemini labels to local ones
        let mapped: String
        switch label {
        case "HEALTH":        mapped = "WELLNESS"
        case "STUDY":         mapped = "LEARN"
        case "FINANCE":       mapped = "MONEY"
        case "MENTAL HEALTH": mapped = "MIND"
        case "OTHER":         mapped = "LIFE"
        default:              mapped = label
        }
        if let b = buckets.first(where: { $0.label == mapped }) {
            return TaskCategory(label: b.label, hue: b.hue, saturation: b.sat, brightness: b.bri)
        }
        if mapped == "LIFE" { return fallback }
        return fallback
    }

    static func activityType(for category: TaskCategory) -> ActivityType {
        switch category.label {
        case "SPORT", "WELLNESS": return .habit
        case "MIND", "LEARN":     return .goal
        default:                   return .task
        }
    }
}
