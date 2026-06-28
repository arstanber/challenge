// Shared language helpers for edge functions that compose user-facing text
// server-side (pushes, Telegram messages, AI prompts). Four languages:
// English, Russian, German, Kazakh -- anything unrecognised falls back to
// English. The active language comes from users.language (synced from the
// device locale by the app, see Swift AppLanguage.current).

export type Lang = "en" | "ru" | "de" | "kk";

const KNOWN: ReadonlySet<string> = new Set(["en", "ru", "de", "kk"]);

export function pickLang(raw: unknown): Lang {
  return typeof raw === "string" && KNOWN.has(raw) ? raw as Lang : "en";
}

// English language name used inside English-written AI prompts to tell the
// model which language to answer in.
const LANG_NAME: Record<Lang, string> = {
  en: "English",
  ru: "Russian",
  de: "German",
  kk: "Kazakh",
};

/** "Respond in <Language>." -- drop-in for the langNote in AI prompts. */
export function respondIn(lang: Lang): string {
  return `Respond in ${LANG_NAME[lang]}.`;
}

/** "Write the explanation in <Language>." -- verify-report variant. */
export function writeExplanationIn(lang: Lang): string {
  return `Write the explanation in ${LANG_NAME[lang]}.`;
}

/** BCP-47 tag for Intl date/number formatting. */
export function localeTag(lang: Lang): string {
  return { en: "en-US", ru: "ru-RU", de: "de-DE", kk: "kk-KZ" }[lang];
}

// ---------------------------------------------------------------------------
// Telegram bot message dictionary -- keyed by message id, each entry either a
// plain string or a builder function for messages with dynamic parts.
// ---------------------------------------------------------------------------

type Entry = string | ((...args: string[]) => string);

const T: Record<string, Record<Lang, Entry>> = {
  startWelcome: {
    en: "👋 Welcome to <b>reInspire</b>!\n\nTo link this chat to your account, open the app → Profile → Telegram bot, " +
      "tap <i>Generate code</i>, then send it here as:\n<code>/start YOUR_CODE</code>",
    ru: "👋 Добро пожаловать в <b>reInspire</b>!\n\nЧтобы привязать этот чат к своему аккаунту, открой приложение → Профиль → Telegram-бот, " +
      "нажми <i>Сгенерировать код</i>, затем отправь его сюда так:\n<code>/start ТВОЙ_КОД</code>",
    de: "👋 Willkommen bei <b>reInspire</b>!\n\nUm diesen Chat mit deinem Konto zu verknüpfen, öffne die App → Profil → Telegram-Bot, " +
      "tippe auf <i>Code generieren</i> und sende ihn hier so:\n<code>/start DEIN_CODE</code>",
    kk: "👋 <b>reInspire</b>-ге қош келдің!\n\nБұл чатты аккаунтыңа байланыстыру үшін қолданбаны аш → Профиль → Telegram бот, " +
      "<i>Код жасау</i> дегенді бас, сосын оны осында былай жібер:\n<code>/start СЕНІҢ_КОДЫҢ</code>",
  },
  startInvalidCode: {
    en: "❌ That code is invalid or expired. Generate a new one in the app and try again.",
    ru: "❌ Этот код недействителен или истёк. Сгенерируй новый в приложении и попробуй снова.",
    de: "❌ Dieser Code ist ungültig oder abgelaufen. Generiere in der App einen neuen und versuch es erneut.",
    kk: "❌ Бұл код жарамсыз немесе мерзімі өткен. Қолданбада жаңасын жасап, қайталап көр.",
  },
  startLinked: {
    en: "✅ Linked! You can now:\n" +
      "• Send a message to create a new task\n" +
      "• Send a photo to submit proof for a task (add a caption with the task name if you have several)\n" +
      "• /today — see today's active tasks\n" +
      "• /done — mark a task complete\n" +
      "• /delete — remove a task\n" +
      "• /history — your recent photo reports\n" +
      "• /stats — your stats and streaks\n" +
      "• /help — show this again",
    ru: "✅ Привязано! Теперь можно:\n" +
      "• Отправить сообщение, чтобы создать новую задачу\n" +
      "• Отправить фото, чтобы подтвердить задачу (добавь подпись с названием задачи, если их несколько)\n" +
      "• /today — задачи на сегодня\n" +
      "• /done — отметить задачу выполненной\n" +
      "• /delete — удалить задачу\n" +
      "• /history — последние фотоотчёты\n" +
      "• /stats — статистика и серии\n" +
      "• /help — показать это снова",
    de: "✅ Verknüpft! Du kannst jetzt:\n" +
      "• Eine Nachricht senden, um eine neue Aufgabe zu erstellen\n" +
      "• Ein Foto senden, um eine Aufgabe nachzuweisen (füge eine Bildunterschrift mit dem Aufgabennamen hinzu, falls du mehrere hast)\n" +
      "• /today — heutige aktive Aufgaben anzeigen\n" +
      "• /done — eine Aufgabe als erledigt markieren\n" +
      "• /delete — eine Aufgabe entfernen\n" +
      "• /history — deine letzten Fotoberichte\n" +
      "• /stats — deine Statistik und Serien\n" +
      "• /help — das hier erneut anzeigen",
    kk: "✅ Байланыстырылды! Енді мынаны істей аласың:\n" +
      "• Жаңа тапсырма жасау үшін хабарлама жібер\n" +
      "• Тапсырманы растау үшін фото жібер (бірнешеуі болса, тапсырма атауын қолтаңбаға қос)\n" +
      "• /today — бүгінгі белсенді тапсырмалар\n" +
      "• /done — тапсырманы орындалды деп белгілеу\n" +
      "• /delete — тапсырманы жою\n" +
      "• /history — соңғы фото есептерің\n" +
      "• /stats — статистикаң мен серияларың\n" +
      "• /help — мұны қайта көрсету",
  },
  help: {
    en: "<b>Commands</b>\n" +
      "• Send any text → creates a new task with that title\n" +
      "• Send a photo → submits proof for a task (caption = task name if you have several active)\n" +
      "• /today — list today's active tasks\n" +
      "• /done — pick a task to mark complete\n" +
      "• /delete — pick a task to remove\n" +
      "• /history — your last few photo reports\n" +
      "• /stats — your stats and streaks\n" +
      "• /start &lt;code&gt; — link your account",
    ru: "<b>Команды</b>\n" +
      "• Любой текст → создаёт новую задачу с этим названием\n" +
      "• Фото → отправляет подтверждение задачи (подпись = название задачи, если их несколько активных)\n" +
      "• /today — список задач на сегодня\n" +
      "• /done — выбрать задачу и отметить выполненной\n" +
      "• /delete — выбрать задачу и удалить\n" +
      "• /history — последние фотоотчёты\n" +
      "• /stats — статистика и серии\n" +
      "• /start &lt;код&gt; — привязать аккаунт",
    de: "<b>Befehle</b>\n" +
      "• Beliebiger Text → erstellt eine neue Aufgabe mit diesem Titel\n" +
      "• Foto → reicht einen Nachweis für eine Aufgabe ein (Bildunterschrift = Aufgabenname, falls mehrere aktiv sind)\n" +
      "• /today — heutige aktive Aufgaben auflisten\n" +
      "• /done — eine Aufgabe zum Abschließen auswählen\n" +
      "• /delete — eine Aufgabe zum Entfernen auswählen\n" +
      "• /history — deine letzten Fotoberichte\n" +
      "• /stats — deine Statistik und Serien\n" +
      "• /start &lt;Code&gt; — dein Konto verknüpfen",
    kk: "<b>Командалар</b>\n" +
      "• Кез келген мәтін → осы атаумен жаңа тапсырма жасайды\n" +
      "• Фото → тапсырманың растамасын жібереді (бірнеше белсенді болса, қолтаңба = тапсырма атауы)\n" +
      "• /today — бүгінгі белсенді тапсырмалар тізімі\n" +
      "• /done — орындалды деп белгілейтін тапсырманы таңда\n" +
      "• /delete — жоятын тапсырманы таңда\n" +
      "• /history — соңғы фото есептерің\n" +
      "• /stats — статистикаң мен серияларың\n" +
      "• /start &lt;код&gt; — аккаунтыңды байланыстыру",
  },
  noTasksToday: {
    en: "You have no tasks scheduled for today. Send me a message to create one!",
    ru: "На сегодня задач нет. Отправь мне сообщение, чтобы создать одну!",
    de: "Für heute sind keine Aufgaben geplant. Schick mir eine Nachricht, um eine zu erstellen!",
    kk: "Бүгінге тапсырма жоспарланбаған. Жаңасын жасау үшін маған хабарлама жібер!",
  },
  todayHeader: { en: "Today's tasks", ru: "Задачи на сегодня", de: "Heutige Aufgaben", kk: "Бүгінгі тапсырмалар" },
  taskCreateFailed: {
    en: "⚠️ Couldn't create that task — please try again from the app.",
    ru: "⚠️ Не удалось создать задачу -- попробуй ещё раз в приложении.",
    de: "⚠️ Aufgabe konnte nicht erstellt werden — bitte versuch es erneut in der App.",
    kk: "⚠️ Тапсырманы жасау мүмкін болмады — қолданбада қайталап көр.",
  },
  taskCreated: {
    en: (title) => `✅ Task created: <b>${title}</b>`,
    ru: (title) => `✅ Задача создана: <b>${title}</b>`,
    de: (title) => `✅ Aufgabe erstellt: <b>${title}</b>`,
    kk: (title) => `✅ Тапсырма жасалды: <b>${title}</b>`,
  },
  noActiveTasks: {
    en: "You have no active tasks right now.",
    ru: "У тебя сейчас нет активных задач.",
    de: "Du hast gerade keine aktiven Aufgaben.",
    kk: "Қазір сенде белсенді тапсырма жоқ.",
  },
  doneListPrompt: {
    en: "Which task did you complete? 🎉",
    ru: "Какую задачу ты выполнил? 🎉",
    de: "Welche Aufgabe hast du erledigt? 🎉",
    kk: "Қай тапсырманы орындадың? 🎉",
  },
  deleteListPrompt: {
    en: "Which task do you want to delete?",
    ru: "Какую задачу хочешь удалить?",
    de: "Welche Aufgabe möchtest du löschen?",
    kk: "Қай тапсырманы жойғың келеді?",
  },
  taskUnavailable: {
    en: "That task is no longer available.",
    ru: "Эта задача больше не доступна.",
    de: "Diese Aufgabe ist nicht mehr verfügbar.",
    kk: "Бұл тапсырма енді қолжетімсіз.",
  },
  taskUnavailableResend: {
    en: "That task is no longer available — please resend the photo.",
    ru: "Эта задача больше не доступна -- отправь фото ещё раз.",
    de: "Diese Aufgabe ist nicht mehr verfügbar — bitte sende das Foto erneut.",
    kk: "Бұл тапсырма енді қолжетімсіз — фотоны қайта жібер.",
  },
  doneRecordFailed: {
    en: "⚠️ Couldn't record that — please try again.",
    ru: "⚠️ Не удалось это записать -- попробуй ещё раз.",
    de: "⚠️ Konnte das nicht speichern — bitte versuch es erneut.",
    kk: "⚠️ Мұны жазу мүмкін болмады — қайталап көр.",
  },
  taskDone: {
    en: (title) => `✅ Marked <b>${title}</b> as done. Nice work!`,
    ru: (title) => `✅ Отметил <b>${title}</b> как выполненную. Отличная работа!`,
    de: (title) => `✅ <b>${title}</b> als erledigt markiert. Gut gemacht!`,
    kk: (title) => `✅ <b>${title}</b> орындалды деп белгіледім. Жарайсың!`,
  },
  deleteConfirmPrompt: {
    en: (title) => `Delete <b>${title}</b>? This can't be undone.`,
    ru: (title) => `Удалить <b>${title}</b>? Это нельзя отменить.`,
    de: (title) => `<b>${title}</b> löschen? Das kann nicht rückgängig gemacht werden.`,
    kk: (title) => `<b>${title}</b> жою керек пе? Мұны қайтару мүмкін емес.`,
  },
  deleteYes: { en: "🗑 Yes, delete", ru: "🗑 Да, удалить", de: "🗑 Ja, löschen", kk: "🗑 Иә, жою" },
  cancel: { en: "Cancel", ru: "Отмена", de: "Abbrechen", kk: "Болдырмау" },
  taskDeleted: {
    en: (title) => `🗑 Deleted <b>${title}</b>.`,
    ru: (title) => `🗑 Удалено: <b>${title}</b>.`,
    de: (title) => `🗑 <b>${title}</b> gelöscht.`,
    kk: (title) => `🗑 <b>${title}</b> жойылды.`,
  },
  noTasksYet: {
    en: "No tasks yet — send me a message to create one!",
    ru: "Задач пока нет -- отправь мне сообщение, чтобы создать одну!",
    de: "Noch keine Aufgaben — schick mir eine Nachricht, um eine zu erstellen!",
    kk: "Әзірге тапсырма жоқ — жаңасын жасау үшін маған хабарлама жібер!",
  },
  statsHeader: { en: "Your stats", ru: "Твоя статистика", de: "Deine Statistik", kk: "Сенің статистикаң" },
  statsBody: {
    en: (active, completed, failed, currentStreak, bestStreak) =>
      `📋 Active: ${active} · ✅ Completed: ${completed} · ❌ Failed: ${failed}\n` +
      `🔥 Current streak: ${currentStreak} · 🏆 Best streak: ${bestStreak}`,
    ru: (active, completed, failed, currentStreak, bestStreak) =>
      `📋 Активные: ${active} · ✅ Завершённые: ${completed} · ❌ Проваленные: ${failed}\n` +
      `🔥 Текущая серия: ${currentStreak} · 🏆 Лучшая серия: ${bestStreak}`,
    de: (active, completed, failed, currentStreak, bestStreak) =>
      `📋 Aktiv: ${active} · ✅ Erledigt: ${completed} · ❌ Fehlgeschlagen: ${failed}\n` +
      `🔥 Aktuelle Serie: ${currentStreak} · 🏆 Beste Serie: ${bestStreak}`,
    kk: (active, completed, failed, currentStreak, bestStreak) =>
      `📋 Белсенді: ${active} · ✅ Орындалған: ${completed} · ❌ Сәтсіз: ${failed}\n` +
      `🔥 Ағымдағы серия: ${currentStreak} · 🏆 Үздік серия: ${bestStreak}`,
  },
  statsReportLine: {
    en: (approved, rejected, excused) =>
      `\n\n<b>Photo proofs</b>\n✅ Approved: ${approved} · ❌ Rejected: ${rejected} · 🙏 Excused: ${excused}`,
    ru: (approved, rejected, excused) =>
      `\n\n<b>Фотоотчёты</b>\n✅ Одобрено: ${approved} · ❌ Отклонено: ${rejected} · 🙏 С отсрочкой: ${excused}`,
    de: (approved, rejected, excused) =>
      `\n\n<b>Fotonachweise</b>\n✅ Genehmigt: ${approved} · ❌ Abgelehnt: ${rejected} · 🙏 Entschuldigt: ${excused}`,
    kk: (approved, rejected, excused) =>
      `\n\n<b>Фото растамалар</b>\n✅ Қабылданды: ${approved} · ❌ Қабылданбады: ${rejected} · 🙏 Дәлелмен: ${excused}`,
  },
  noReportsYet: {
    en: "No reports yet — submit a photo to get started.",
    ru: "Отчётов пока нет -- отправь фото, чтобы начать.",
    de: "Noch keine Berichte — reiche ein Foto ein, um loszulegen.",
    kk: "Әзірге есеп жоқ — бастау үшін фото жібер.",
  },
  recentReportsHeader: { en: "Recent reports", ru: "Последние отчёты", de: "Letzte Berichte", kk: "Соңғы есептер" },
  taskFallbackTitle: { en: "Task", ru: "Задача", de: "Aufgabe", kk: "Тапсырма" },
  noActiveTasksCreate: {
    en: "You don't have any active tasks yet. Send a text message to create one.",
    ru: "У тебя пока нет активных задач. Отправь текстовое сообщение, чтобы создать одну.",
    de: "Du hast noch keine aktiven Aufgaben. Sende eine Textnachricht, um eine zu erstellen.",
    kk: "Сенде әзірге белсенді тапсырма жоқ. Жаңасын жасау үшін мәтін хабарламасын жібер.",
  },
  taskNotFoundByCaption: {
    en: (caption, list) => `Couldn't find an active task matching "${caption}". Your active tasks:\n${list}`,
    ru: (caption, list) => `Не нашёл активную задачу по запросу "${caption}". Твои активные задачи:\n${list}`,
    de: (caption, list) => `Keine aktive Aufgabe zu "${caption}" gefunden. Deine aktiven Aufgaben:\n${list}`,
    kk: (caption, list) => `"${caption}" сұрауына сәйкес белсенді тапсырма табылмады. Белсенді тапсырмаларың:\n${list}`,
  },
  photoPickPrompt: {
    en: "📸 Got it — which task is this photo for?",
    ru: "📸 Принято -- для какой задачи это фото?",
    de: "📸 Verstanden — für welche Aufgabe ist dieses Foto?",
    kk: "📸 Қабылдадым — бұл фото қай тапсырма үшін?",
  },
  verifying: {
    en: (title) => `📸 Got it — verifying <b>${title}</b>...`,
    ru: (title) => `📸 Принято -- проверяю <b>${title}</b>...`,
    de: (title) => `📸 Verstanden — prüfe <b>${title}</b>...`,
    kk: (title) => `📸 Қабылдадым — <b>${title}</b> тексерудемін...`,
  },
  photoPromptExpired: {
    en: "That photo prompt expired — please resend the photo.",
    ru: "Запрос на фото истёк -- отправь фото ещё раз.",
    de: "Die Foto-Anfrage ist abgelaufen — bitte sende das Foto erneut.",
    kk: "Фото сұрауының мерзімі өтті — фотоны қайта жібер.",
  },
  proofSubmitted: {
    en: (title) => `✅ Proof submitted for <b>${title}</b>.`,
    ru: (title) => `✅ Подтверждение отправлено для <b>${title}</b>.`,
    de: (title) => `✅ Nachweis für <b>${title}</b> eingereicht.`,
    kk: (title) => `✅ <b>${title}</b> үшін растама жіберілді.`,
  },
  verifyError: {
    en: "⚠️ Something went wrong while verifying that photo — please try again.",
    ru: "⚠️ Что-то пошло не так при проверке фото -- попробуй ещё раз.",
    de: "⚠️ Beim Prüfen des Fotos ist etwas schiefgelaufen — bitte versuch es erneut.",
    kk: "⚠️ Фотоны тексеру кезінде бірдеңе дұрыс болмады — қайталап көр.",
  },
  deleteCancelled: {
    en: "Cancelled — that task is still there.",
    ru: "Отменено -- задача осталась на месте.",
    de: "Abgebrochen — die Aufgabe ist noch da.",
    kk: "Болдырылмады — тапсырма орнында қалды.",
  },
  genericError: {
    en: "⚠️ Something went wrong handling that — please try again.",
    ru: "⚠️ Что-то пошло не так -- попробуй ещё раз.",
    de: "⚠️ Bei der Verarbeitung ist etwas schiefgelaufen — bitte versuch es erneut.",
    kk: "⚠️ Өңдеу кезінде бірдеңе дұрыс болмады — қайталап көр.",
  },
};

export function t(lang: Lang, key: keyof typeof T, ...args: string[]): string {
  const entry = T[key][lang];
  return typeof entry === "function" ? entry(...args) : entry;
}
