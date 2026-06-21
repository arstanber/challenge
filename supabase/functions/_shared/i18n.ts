// Shared EN/RU language helpers for edge functions that compose user-facing
// text server-side (pushes, Telegram messages, AI prompts). Two languages
// only -- anything that isn't exactly "ru" is treated as English.

export type Lang = "en" | "ru";

export function pickLang(raw: unknown): Lang {
  return raw === "ru" ? "ru" : "en";
}

// ---------------------------------------------------------------------------
// Telegram bot message dictionary -- keyed by message id, each entry either a
// plain string or a builder function for messages with dynamic parts.
// ---------------------------------------------------------------------------

type Entry = string | ((...args: string[]) => string);

const T: Record<string, { en: Entry; ru: Entry }> = {
  startWelcome: {
    en: "👋 Welcome to <b>reInspire</b>!\n\nTo link this chat to your account, open the app → Profile → Telegram bot, " +
      "tap <i>Generate code</i>, then send it here as:\n<code>/start YOUR_CODE</code>",
    ru: "👋 Добро пожаловать в <b>reInspire</b>!\n\nЧтобы привязать этот чат к своему аккаунту, открой приложение → Профиль → Telegram-бот, " +
      "нажми <i>Сгенерировать код</i>, затем отправь его сюда так:\n<code>/start ТВОЙ_КОД</code>",
  },
  startInvalidCode: {
    en: "❌ That code is invalid or expired. Generate a new one in the app and try again.",
    ru: "❌ Этот код недействителен или истёк. Сгенерируй новый в приложении и попробуй снова.",
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
  },
  noTasksToday: {
    en: "You have no tasks scheduled for today. Send me a message to create one!",
    ru: "На сегодня задач нет. Отправь мне сообщение, чтобы создать одну!",
  },
  todayHeader: { en: "Today's tasks", ru: "Задачи на сегодня" },
  taskCreateFailed: {
    en: "⚠️ Couldn't create that task — please try again from the app.",
    ru: "⚠️ Не удалось создать задачу -- попробуй ещё раз в приложении.",
  },
  taskCreated: {
    en: (title) => `✅ Task created: <b>${title}</b>`,
    ru: (title) => `✅ Задача создана: <b>${title}</b>`,
  },
  noActiveTasks: {
    en: "You have no active tasks right now.",
    ru: "У тебя сейчас нет активных задач.",
  },
  doneListPrompt: {
    en: "Which task did you complete? 🎉",
    ru: "Какую задачу ты выполнил? 🎉",
  },
  deleteListPrompt: {
    en: "Which task do you want to delete?",
    ru: "Какую задачу хочешь удалить?",
  },
  taskUnavailable: {
    en: "That task is no longer available.",
    ru: "Эта задача больше не доступна.",
  },
  taskUnavailableResend: {
    en: "That task is no longer available — please resend the photo.",
    ru: "Эта задача больше не доступна -- отправь фото ещё раз.",
  },
  doneRecordFailed: {
    en: "⚠️ Couldn't record that — please try again.",
    ru: "⚠️ Не удалось это записать -- попробуй ещё раз.",
  },
  taskDone: {
    en: (title) => `✅ Marked <b>${title}</b> as done. Nice work!`,
    ru: (title) => `✅ Отметил <b>${title}</b> как выполненную. Отличная работа!`,
  },
  deleteConfirmPrompt: {
    en: (title) => `Delete <b>${title}</b>? This can't be undone.`,
    ru: (title) => `Удалить <b>${title}</b>? Это нельзя отменить.`,
  },
  deleteYes: { en: "🗑 Yes, delete", ru: "🗑 Да, удалить" },
  cancel: { en: "Cancel", ru: "Отмена" },
  taskDeleted: {
    en: (title) => `🗑 Deleted <b>${title}</b>.`,
    ru: (title) => `🗑 Удалено: <b>${title}</b>.`,
  },
  noTasksYet: {
    en: "No tasks yet — send me a message to create one!",
    ru: "Задач пока нет -- отправь мне сообщение, чтобы создать одну!",
  },
  statsHeader: { en: "Your stats", ru: "Твоя статистика" },
  statsBody: {
    en: (active, completed, failed, currentStreak, bestStreak) =>
      `📋 Active: ${active} · ✅ Completed: ${completed} · ❌ Failed: ${failed}\n` +
      `🔥 Current streak: ${currentStreak} · 🏆 Best streak: ${bestStreak}`,
    ru: (active, completed, failed, currentStreak, bestStreak) =>
      `📋 Активные: ${active} · ✅ Завершённые: ${completed} · ❌ Проваленные: ${failed}\n` +
      `🔥 Текущая серия: ${currentStreak} · 🏆 Лучшая серия: ${bestStreak}`,
  },
  statsReportLine: {
    en: (approved, rejected, excused) =>
      `\n\n<b>Photo proofs</b>\n✅ Approved: ${approved} · ❌ Rejected: ${rejected} · 🙏 Excused: ${excused}`,
    ru: (approved, rejected, excused) =>
      `\n\n<b>Фотоотчёты</b>\n✅ Одобрено: ${approved} · ❌ Отклонено: ${rejected} · 🙏 С отсрочкой: ${excused}`,
  },
  noReportsYet: {
    en: "No reports yet — submit a photo to get started.",
    ru: "Отчётов пока нет -- отправь фото, чтобы начать.",
  },
  recentReportsHeader: { en: "Recent reports", ru: "Последние отчёты" },
  taskFallbackTitle: { en: "Task", ru: "Задача" },
  noActiveTasksCreate: {
    en: "You don't have any active tasks yet. Send a text message to create one.",
    ru: "У тебя пока нет активных задач. Отправь текстовое сообщение, чтобы создать одну.",
  },
  taskNotFoundByCaption: {
    en: (caption, list) => `Couldn't find an active task matching "${caption}". Your active tasks:\n${list}`,
    ru: (caption, list) => `Не нашёл активную задачу по запросу "${caption}". Твои активные задачи:\n${list}`,
  },
  photoPickPrompt: {
    en: "📸 Got it — which task is this photo for?",
    ru: "📸 Принято -- для какой задачи это фото?",
  },
  verifying: {
    en: (title) => `📸 Got it — verifying <b>${title}</b>...`,
    ru: (title) => `📸 Принято -- проверяю <b>${title}</b>...`,
  },
  photoPromptExpired: {
    en: "That photo prompt expired — please resend the photo.",
    ru: "Запрос на фото истёк -- отправь фото ещё раз.",
  },
  proofSubmitted: {
    en: (title) => `✅ Proof submitted for <b>${title}</b>.`,
    ru: (title) => `✅ Подтверждение отправлено для <b>${title}</b>.`,
  },
  verifyError: {
    en: "⚠️ Something went wrong while verifying that photo — please try again.",
    ru: "⚠️ Что-то пошло не так при проверке фото -- попробуй ещё раз.",
  },
  deleteCancelled: {
    en: "Cancelled — that task is still there.",
    ru: "Отменено -- задача осталась на месте.",
  },
  genericError: {
    en: "⚠️ Something went wrong handling that — please try again.",
    ru: "⚠️ Что-то пошло не так -- попробуй ещё раз.",
  },
};

export function t(lang: Lang, key: keyof typeof T, ...args: string[]): string {
  const entry = T[key][lang];
  return typeof entry === "function" ? entry(...args) : entry;
}
