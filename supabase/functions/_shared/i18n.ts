// Shared language helpers for edge functions that compose user-facing text
// server-side (pushes, Telegram messages, AI prompts). Six languages:
// English, Russian, German, Kazakh, French, Arabic -- anything unrecognised
// falls back to English. The active language comes from users.language
// (synced from the device locale by the app, see Swift AppLanguage.current).
//
// Keep this list in sync with AppLanguage.supported, the pbxproj knownRegions,
// and both .xcstrings catalogs -- a language added in one place and not the
// others degrades silently to English rather than failing.

export type Lang = "en" | "ru" | "de" | "kk" | "fr" | "ar";

const KNOWN: ReadonlySet<string> = new Set(["en", "ru", "de", "kk", "fr", "ar"]);

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
  fr: "French",
  ar: "Arabic",
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
  return {
    en: "en-US",
    ru: "ru-RU",
    de: "de-DE",
    kk: "kk-KZ",
    fr: "fr-FR",
    ar: "ar-SA",
  }[lang];
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
    fr: "👋 Bienvenue sur <b>reInspire</b> !\n\nPour lier ce chat à ton compte, ouvre l'app → Profil → Bot Telegram, " +
      "appuie sur <i>Générer un code</i>, puis envoie-le ici ainsi :\n<code>/start TON_CODE</code>",
    ar: "👋 أهلًا بك في <b>reInspire</b>!\n\nلربط هذه المحادثة بحسابك، افتح التطبيق ← الملف الشخصي ← بوت Telegram، " +
      "اضغط على <i>إنشاء رمز</i>، ثم أرسله هنا هكذا:\n<code>/start رمزك</code>",
  },
  startInvalidCode: {
    en: "❌ That code is invalid or expired. Generate a new one in the app and try again.",
    ru: "❌ Этот код недействителен или истёк. Сгенерируй новый в приложении и попробуй снова.",
    de: "❌ Dieser Code ist ungültig oder abgelaufen. Generiere in der App einen neuen und versuch es erneut.",
    kk: "❌ Бұл код жарамсыз немесе мерзімі өткен. Қолданбада жаңасын жасап, қайталап көр.",
    fr: "❌ Ce code est invalide ou expiré. Génère-en un nouveau dans l'app et réessaie.",
    ar: "❌ هذا الرمز غير صالح أو منتهي الصلاحية. أنشئ رمزًا جديدًا في التطبيق وحاول مرة أخرى.",
  },
  startLinked: {
    en: "✅ Linked! You can now:\n" +
      "• Send a message to create a new task\n" +
      "• Send a photo to submit proof for a task (add a caption with the task name if you have several)\n" +
      "• /today -- see today's active tasks\n" +
      "• /done -- mark a task complete\n" +
      "• /delete -- remove a task\n" +
      "• /history -- your recent photo reports\n" +
      "• /stats -- your stats and streaks\n" +
      "• /help -- show this again",
    ru: "✅ Привязано! Теперь можно:\n" +
      "• Отправить сообщение, чтобы создать новую задачу\n" +
      "• Отправить фото, чтобы подтвердить задачу (добавь подпись с названием задачи, если их несколько)\n" +
      "• /today -- задачи на сегодня\n" +
      "• /done -- отметить задачу выполненной\n" +
      "• /delete -- удалить задачу\n" +
      "• /history -- последние фотоотчёты\n" +
      "• /stats -- статистика и серии\n" +
      "• /help -- показать это снова",
    de: "✅ Verknüpft! Du kannst jetzt:\n" +
      "• Eine Nachricht senden, um eine neue Aufgabe zu erstellen\n" +
      "• Ein Foto senden, um eine Aufgabe nachzuweisen (füge eine Bildunterschrift mit dem Aufgabennamen hinzu, falls du mehrere hast)\n" +
      "• /today -- heutige aktive Aufgaben anzeigen\n" +
      "• /done -- eine Aufgabe als erledigt markieren\n" +
      "• /delete -- eine Aufgabe entfernen\n" +
      "• /history -- deine letzten Fotoberichte\n" +
      "• /stats -- deine Statistik und Serien\n" +
      "• /help -- das hier erneut anzeigen",
    kk: "✅ Байланыстырылды! Енді мынаны істей аласың:\n" +
      "• Жаңа тапсырма жасау үшін хабарлама жібер\n" +
      "• Тапсырманы растау үшін фото жібер (бірнешеуі болса, тапсырма атауын қолтаңбаға қос)\n" +
      "• /today -- бүгінгі белсенді тапсырмалар\n" +
      "• /done -- тапсырманы орындалды деп белгілеу\n" +
      "• /delete -- тапсырманы жою\n" +
      "• /history -- соңғы фото есептерің\n" +
      "• /stats -- статистикаң мен серияларың\n" +
      "• /help -- мұны қайта көрсету",
    fr: "✅ Lié ! Tu peux maintenant :\n" +
      "• Envoyer un message pour créer une nouvelle tâche\n" +
      "• Envoyer une photo pour prouver une tâche (ajoute une légende avec le nom de la tâche si tu en as plusieurs)\n" +
      "• /today -- voir les tâches actives du jour\n" +
      "• /done -- marquer une tâche comme faite\n" +
      "• /delete -- supprimer une tâche\n" +
      "• /history -- tes derniers rapports photo\n" +
      "• /stats -- tes stats et tes séries\n" +
      "• /help -- réafficher ceci",
    ar: "✅ تم الربط! يمكنك الآن:\n" +
      "• إرسال رسالة لإنشاء مهمة جديدة\n" +
      "• إرسال صورة لإثبات مهمة (أضف تعليقًا باسم المهمة إذا كان لديك أكثر من واحدة)\n" +
      "• ‎/today -- عرض مهام اليوم النشطة\n" +
      "• ‎/done -- وضع علامة على مهمة كمنجزة\n" +
      "• ‎/delete -- حذف مهمة\n" +
      "• ‎/history -- آخر تقاريرك المصوّرة\n" +
      "• ‎/stats -- إحصاءاتك وسلاسلك\n" +
      "• ‎/help -- عرض هذه الرسالة مرة أخرى",
  },
  help: {
    en: "<b>Commands</b>\n" +
      "• Send any text → creates a new task with that title\n" +
      "• Send a photo → submits proof for a task (caption = task name if you have several active)\n" +
      "• /today -- list today's active tasks\n" +
      "• /done -- pick a task to mark complete\n" +
      "• /delete -- pick a task to remove\n" +
      "• /history -- your last few photo reports\n" +
      "• /stats -- your stats and streaks\n" +
      "• /start &lt;code&gt; -- link your account",
    ru: "<b>Команды</b>\n" +
      "• Любой текст → создаёт новую задачу с этим названием\n" +
      "• Фото → отправляет подтверждение задачи (подпись = название задачи, если их несколько активных)\n" +
      "• /today -- список задач на сегодня\n" +
      "• /done -- выбрать задачу и отметить выполненной\n" +
      "• /delete -- выбрать задачу и удалить\n" +
      "• /history -- последние фотоотчёты\n" +
      "• /stats -- статистика и серии\n" +
      "• /start &lt;код&gt; -- привязать аккаунт",
    de: "<b>Befehle</b>\n" +
      "• Beliebiger Text → erstellt eine neue Aufgabe mit diesem Titel\n" +
      "• Foto → reicht einen Nachweis für eine Aufgabe ein (Bildunterschrift = Aufgabenname, falls mehrere aktiv sind)\n" +
      "• /today -- heutige aktive Aufgaben auflisten\n" +
      "• /done -- eine Aufgabe zum Abschließen auswählen\n" +
      "• /delete -- eine Aufgabe zum Entfernen auswählen\n" +
      "• /history -- deine letzten Fotoberichte\n" +
      "• /stats -- deine Statistik und Serien\n" +
      "• /start &lt;Code&gt; -- dein Konto verknüpfen",
    kk: "<b>Командалар</b>\n" +
      "• Кез келген мәтін → осы атаумен жаңа тапсырма жасайды\n" +
      "• Фото → тапсырманың растамасын жібереді (бірнеше белсенді болса, қолтаңба = тапсырма атауы)\n" +
      "• /today -- бүгінгі белсенді тапсырмалар тізімі\n" +
      "• /done -- орындалды деп белгілейтін тапсырманы таңда\n" +
      "• /delete -- жоятын тапсырманы таңда\n" +
      "• /history -- соңғы фото есептерің\n" +
      "• /stats -- статистикаң мен серияларың\n" +
      "• /start &lt;код&gt; -- аккаунтыңды байланыстыру",
    fr: "<b>Commandes</b>\n" +
      "• N'importe quel texte → crée une nouvelle tâche avec ce titre\n" +
      "• Photo → envoie une preuve pour une tâche (légende = nom de la tâche si plusieurs sont actives)\n" +
      "• /today -- lister les tâches actives du jour\n" +
      "• /done -- choisir une tâche à marquer comme faite\n" +
      "• /delete -- choisir une tâche à supprimer\n" +
      "• /history -- tes derniers rapports photo\n" +
      "• /stats -- tes stats et tes séries\n" +
      "• /start &lt;code&gt; -- lier ton compte",
    ar: "<b>الأوامر</b>\n" +
      "• أي نص ← ينشئ مهمة جديدة بهذا العنوان\n" +
      "• صورة ← يرسل إثباتًا لمهمة (التعليق = اسم المهمة إذا كان لديك عدة مهام نشطة)\n" +
      "• ‎/today -- عرض قائمة مهام اليوم النشطة\n" +
      "• ‎/done -- اختيار مهمة لوضع علامة منجزة\n" +
      "• ‎/delete -- اختيار مهمة لحذفها\n" +
      "• ‎/history -- آخر تقاريرك المصوّرة\n" +
      "• ‎/stats -- إحصاءاتك وسلاسلك\n" +
      "• ‎/start &lt;الرمز&gt; -- ربط حسابك",
  },
  noTasksToday: {
    en: "You have no tasks scheduled for today. Send me a message to create one!",
    ru: "На сегодня задач нет. Отправь мне сообщение, чтобы создать одну!",
    de: "Für heute sind keine Aufgaben geplant. Schick mir eine Nachricht, um eine zu erstellen!",
    kk: "Бүгінге тапсырма жоспарланбаған. Жаңасын жасау үшін маған хабарлама жібер!",
    fr: "Aucune tâche prévue pour aujourd'hui. Envoie-moi un message pour en créer une !",
    ar: "لا توجد مهام مجدولة لليوم. أرسل لي رسالة لإنشاء واحدة!",
  },
  todayHeader: {
    en: "Today's tasks",
    ru: "Задачи на сегодня",
    de: "Heutige Aufgaben",
    kk: "Бүгінгі тапсырмалар",
    fr: "Tâches du jour",
    ar: "مهام اليوم",
  },
  taskCreateFailed: {
    en: "⚠️ Couldn't create that task -- please try again from the app.",
    ru: "⚠️ Не удалось создать задачу -- попробуй ещё раз в приложении.",
    de: "⚠️ Aufgabe konnte nicht erstellt werden -- bitte versuch es erneut in der App.",
    kk: "⚠️ Тапсырманы жасау мүмкін болмады -- қолданбада қайталап көр.",
    fr: "⚠️ Impossible de créer cette tâche -- réessaie depuis l'app.",
    ar: "⚠️ تعذّر إنشاء هذه المهمة -- حاول مرة أخرى من التطبيق.",
  },
  taskCreated: {
    en: (title) => `✅ Task created: <b>${title}</b>`,
    ru: (title) => `✅ Задача создана: <b>${title}</b>`,
    de: (title) => `✅ Aufgabe erstellt: <b>${title}</b>`,
    kk: (title) => `✅ Тапсырма жасалды: <b>${title}</b>`,
    fr: (title) => `✅ Tâche créée : <b>${title}</b>`,
    ar: (title) => `✅ تم إنشاء المهمة: <b>${title}</b>`,
  },
  noActiveTasks: {
    en: "You have no active tasks right now.",
    ru: "У тебя сейчас нет активных задач.",
    de: "Du hast gerade keine aktiven Aufgaben.",
    kk: "Қазір сенде белсенді тапсырма жоқ.",
    fr: "Tu n'as aucune tâche active pour le moment.",
    ar: "ليس لديك مهام نشطة حاليًا.",
  },
  doneListPrompt: {
    en: "Which task did you complete? 🎉",
    ru: "Какую задачу ты выполнил? 🎉",
    de: "Welche Aufgabe hast du erledigt? 🎉",
    kk: "Қай тапсырманы орындадың? 🎉",
    fr: "Quelle tâche as-tu terminée ? 🎉",
    ar: "أي مهمة أنجزت؟ 🎉",
  },
  deleteListPrompt: {
    en: "Which task do you want to delete?",
    ru: "Какую задачу хочешь удалить?",
    de: "Welche Aufgabe möchtest du löschen?",
    kk: "Қай тапсырманы жойғың келеді?",
    fr: "Quelle tâche veux-tu supprimer ?",
    ar: "أي مهمة تريد حذفها؟",
  },
  taskUnavailable: {
    en: "That task is no longer available.",
    ru: "Эта задача больше не доступна.",
    de: "Diese Aufgabe ist nicht mehr verfügbar.",
    kk: "Бұл тапсырма енді қолжетімсіз.",
    fr: "Cette tâche n'est plus disponible.",
    ar: "هذه المهمة لم تعد متاحة.",
  },
  taskUnavailableResend: {
    en: "That task is no longer available -- please resend the photo.",
    ru: "Эта задача больше не доступна -- отправь фото ещё раз.",
    de: "Diese Aufgabe ist nicht mehr verfügbar -- bitte sende das Foto erneut.",
    kk: "Бұл тапсырма енді қолжетімсіз -- фотоны қайта жібер.",
    fr: "Cette tâche n'est plus disponible -- renvoie la photo.",
    ar: "هذه المهمة لم تعد متاحة -- أعد إرسال الصورة.",
  },
  doneRecordFailed: {
    en: "⚠️ Couldn't record that -- please try again.",
    ru: "⚠️ Не удалось это записать -- попробуй ещё раз.",
    de: "⚠️ Konnte das nicht speichern -- bitte versuch es erneut.",
    kk: "⚠️ Мұны жазу мүмкін болмады -- қайталап көр.",
    fr: "⚠️ Impossible d'enregistrer -- réessaie.",
    ar: "⚠️ تعذّر تسجيل ذلك -- حاول مرة أخرى.",
  },
  taskDone: {
    en: (title) => `✅ Marked <b>${title}</b> as done. Nice work!`,
    ru: (title) => `✅ Отметил <b>${title}</b> как выполненную. Отличная работа!`,
    de: (title) => `✅ <b>${title}</b> als erledigt markiert. Gut gemacht!`,
    kk: (title) => `✅ <b>${title}</b> орындалды деп белгіледім. Жарайсың!`,
    fr: (title) => `✅ <b>${title}</b> marquée comme faite. Beau travail !`,
    ar: (title) => `✅ تم وضع علامة منجزة على <b>${title}</b>. عمل رائع!`,
  },
  deleteConfirmPrompt: {
    en: (title) => `Delete <b>${title}</b>? This can't be undone.`,
    ru: (title) => `Удалить <b>${title}</b>? Это нельзя отменить.`,
    de: (title) => `<b>${title}</b> löschen? Das kann nicht rückgängig gemacht werden.`,
    kk: (title) => `<b>${title}</b> жою керек пе? Мұны қайтару мүмкін емес.`,
    fr: (title) => `Supprimer <b>${title}</b> ? C'est irréversible.`,
    ar: (title) => `حذف <b>${title}</b>؟ لا يمكن التراجع عن هذا.`,
  },
  deleteYes: {
    en: "🗑 Yes, delete",
    ru: "🗑 Да, удалить",
    de: "🗑 Ja, löschen",
    kk: "🗑 Иә, жою",
    fr: "🗑 Oui, supprimer",
    ar: "🗑 نعم، احذف",
  },
  cancel: {
    en: "Cancel",
    ru: "Отмена",
    de: "Abbrechen",
    kk: "Болдырмау",
    fr: "Annuler",
    ar: "إلغاء",
  },
  taskDeleted: {
    en: (title) => `🗑 Deleted <b>${title}</b>.`,
    ru: (title) => `🗑 Удалено: <b>${title}</b>.`,
    de: (title) => `🗑 <b>${title}</b> gelöscht.`,
    kk: (title) => `🗑 <b>${title}</b> жойылды.`,
    fr: (title) => `🗑 <b>${title}</b> supprimée.`,
    ar: (title) => `🗑 تم حذف <b>${title}</b>.`,
  },
  noTasksYet: {
    en: "No tasks yet -- send me a message to create one!",
    ru: "Задач пока нет -- отправь мне сообщение, чтобы создать одну!",
    de: "Noch keine Aufgaben -- schick mir eine Nachricht, um eine zu erstellen!",
    kk: "Әзірге тапсырма жоқ -- жаңасын жасау үшін маған хабарлама жібер!",
    fr: "Pas encore de tâches -- envoie-moi un message pour en créer une !",
    ar: "لا توجد مهام بعد -- أرسل لي رسالة لإنشاء واحدة!",
  },
  statsHeader: {
    en: "Your stats",
    ru: "Твоя статистика",
    de: "Deine Statistik",
    kk: "Сенің статистикаң",
    fr: "Tes stats",
    ar: "إحصاءاتك",
  },
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
    fr: (active, completed, failed, currentStreak, bestStreak) =>
      `📋 Actives : ${active} · ✅ Terminées : ${completed} · ❌ Échouées : ${failed}\n` +
      `🔥 Série en cours : ${currentStreak} · 🏆 Meilleure série : ${bestStreak}`,
    ar: (active, completed, failed, currentStreak, bestStreak) =>
      `📋 نشطة: ${active} · ✅ منجزة: ${completed} · ❌ فاشلة: ${failed}\n` +
      `🔥 السلسلة الحالية: ${currentStreak} · 🏆 أفضل سلسلة: ${bestStreak}`,
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
    fr: (approved, rejected, excused) =>
      `\n\n<b>Preuves photo</b>\n✅ Acceptées : ${approved} · ❌ Refusées : ${rejected} · 🙏 Excusées : ${excused}`,
    ar: (approved, rejected, excused) =>
      `\n\n<b>الإثباتات المصوّرة</b>\n✅ مقبولة: ${approved} · ❌ مرفوضة: ${rejected} · 🙏 معذورة: ${excused}`,
  },
  noReportsYet: {
    en: "No reports yet -- submit a photo to get started.",
    ru: "Отчётов пока нет -- отправь фото, чтобы начать.",
    de: "Noch keine Berichte -- reiche ein Foto ein, um loszulegen.",
    kk: "Әзірге есеп жоқ -- бастау үшін фото жібер.",
    fr: "Pas encore de rapports -- envoie une photo pour commencer.",
    ar: "لا توجد تقارير بعد -- أرسل صورة للبدء.",
  },
  recentReportsHeader: {
    en: "Recent reports",
    ru: "Последние отчёты",
    de: "Letzte Berichte",
    kk: "Соңғы есептер",
    fr: "Rapports récents",
    ar: "أحدث التقارير",
  },
  taskFallbackTitle: {
    en: "Task",
    ru: "Задача",
    de: "Aufgabe",
    kk: "Тапсырма",
    fr: "Tâche",
    ar: "مهمة",
  },
  noActiveTasksCreate: {
    en: "You don't have any active tasks yet. Send a text message to create one.",
    ru: "У тебя пока нет активных задач. Отправь текстовое сообщение, чтобы создать одну.",
    de: "Du hast noch keine aktiven Aufgaben. Sende eine Textnachricht, um eine zu erstellen.",
    kk: "Сенде әзірге белсенді тапсырма жоқ. Жаңасын жасау үшін мәтін хабарламасын жібер.",
    fr: "Tu n'as pas encore de tâche active. Envoie un message texte pour en créer une.",
    ar: "ليس لديك أي مهام نشطة بعد. أرسل رسالة نصية لإنشاء واحدة.",
  },
  taskNotFoundByCaption: {
    en: (caption, list) => `Couldn't find an active task matching "${caption}". Your active tasks:\n${list}`,
    ru: (caption, list) => `Не нашёл активную задачу по запросу "${caption}". Твои активные задачи:\n${list}`,
    de: (caption, list) => `Keine aktive Aufgabe zu "${caption}" gefunden. Deine aktiven Aufgaben:\n${list}`,
    kk: (caption, list) => `"${caption}" сұрауына сәйкес белсенді тапсырма табылмады. Белсенді тапсырмаларың:\n${list}`,
    fr: (caption, list) => `Aucune tâche active ne correspond à "${caption}". Tes tâches actives :\n${list}`,
    ar: (caption, list) => `لم أجد مهمة نشطة تطابق "${caption}". مهامك النشطة:\n${list}`,
  },
  photoPickPrompt: {
    en: "📸 Got it -- which task is this photo for?",
    ru: "📸 Принято -- для какой задачи это фото?",
    de: "📸 Verstanden -- für welche Aufgabe ist dieses Foto?",
    kk: "📸 Қабылдадым -- бұл фото қай тапсырма үшін?",
    fr: "📸 Bien reçu -- pour quelle tâche est cette photo ?",
    ar: "📸 وصلتني -- لأي مهمة هذه الصورة؟",
  },
  verifying: {
    en: (title) => `📸 Got it -- verifying <b>${title}</b>...`,
    ru: (title) => `📸 Принято -- проверяю <b>${title}</b>...`,
    de: (title) => `📸 Verstanden -- prüfe <b>${title}</b>...`,
    kk: (title) => `📸 Қабылдадым -- <b>${title}</b> тексерудемін...`,
    fr: (title) => `📸 Bien reçu -- vérification de <b>${title}</b>...`,
    ar: (title) => `📸 وصلتني -- جارٍ التحقق من <b>${title}</b>...`,
  },
  photoPromptExpired: {
    en: "That photo prompt expired -- please resend the photo.",
    ru: "Запрос на фото истёк -- отправь фото ещё раз.",
    de: "Die Foto-Anfrage ist abgelaufen -- bitte sende das Foto erneut.",
    kk: "Фото сұрауының мерзімі өтті -- фотоны қайта жібер.",
    fr: "Cette demande de photo a expiré -- renvoie la photo.",
    ar: "انتهت صلاحية طلب الصورة -- أعد إرسال الصورة.",
  },
  proofSubmitted: {
    en: (title) => `✅ Proof submitted for <b>${title}</b>.`,
    ru: (title) => `✅ Подтверждение отправлено для <b>${title}</b>.`,
    de: (title) => `✅ Nachweis für <b>${title}</b> eingereicht.`,
    kk: (title) => `✅ <b>${title}</b> үшін растама жіберілді.`,
    fr: (title) => `✅ Preuve envoyée pour <b>${title}</b>.`,
    ar: (title) => `✅ تم إرسال الإثبات لـ <b>${title}</b>.`,
  },
  verifyError: {
    en: "⚠️ Something went wrong while verifying that photo -- please try again.",
    ru: "⚠️ Что-то пошло не так при проверке фото -- попробуй ещё раз.",
    de: "⚠️ Beim Prüfen des Fotos ist etwas schiefgelaufen -- bitte versuch es erneut.",
    kk: "⚠️ Фотоны тексеру кезінде бірдеңе дұрыс болмады -- қайталап көр.",
    fr: "⚠️ Un problème est survenu lors de la vérification de la photo -- réessaie.",
    ar: "⚠️ حدث خطأ أثناء التحقق من الصورة -- حاول مرة أخرى.",
  },
  deleteCancelled: {
    en: "Cancelled -- that task is still there.",
    ru: "Отменено -- задача осталась на месте.",
    de: "Abgebrochen -- die Aufgabe ist noch da.",
    kk: "Болдырылмады -- тапсырма орнында қалды.",
    fr: "Annulé -- la tâche est toujours là.",
    ar: "تم الإلغاء -- المهمة ما زالت موجودة.",
  },
  genericError: {
    en: "⚠️ Something went wrong handling that -- please try again.",
    ru: "⚠️ Что-то пошло не так -- попробуй ещё раз.",
    de: "⚠️ Bei der Verarbeitung ist etwas schiefgelaufen -- bitte versuch es erneut.",
    kk: "⚠️ Өңдеу кезінде бірдеңе дұрыс болмады -- қайталап көр.",
    fr: "⚠️ Un problème est survenu -- réessaie.",
    ar: "⚠️ حدث خطأ أثناء المعالجة -- حاول مرة أخرى.",
  },
};

export function t(lang: Lang, key: keyof typeof T, ...args: string[]): string {
  const entry = T[key][lang];
  return typeof entry === "function" ? entry(...args) : entry;
}
