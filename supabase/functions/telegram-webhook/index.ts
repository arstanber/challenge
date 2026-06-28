// Edge Function: telegram-webhook
// Receives updates from the reInspire Telegram bot and lets users:
//   - link their Telegram account to their app account ("/start <code>")
//   - create new tasks by sending a text message
//   - submit photo proof for a challenge/assignment (runs the same AI
//     verification flow as the in-app camera, via Gemini vision); when several
//     active challenges could match, an inline keyboard lets them pick one
//   - list today's active tasks ("/today")
//   - mark a task done or delete it via inline-keyboard pickers ("/done", "/delete")
//   - view recent photo-report history and stats ("/history", "/stats")
//
// Configure once after deploying:
//   supabase secrets set TELEGRAM_BOT_TOKEN=...        (from @BotFather)
//   supabase secrets set TELEGRAM_WEBHOOK_SECRET=...   (random string you choose)
//   curl -X POST "https://api.telegram.org/bot$TOKEN/setWebhook" \
//        -d "url=$FUNCTIONS_URL/telegram-webhook&secret_token=$TELEGRAM_WEBHOOK_SECRET"

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { type Lang, localeTag, pickLang, t } from "../_shared/i18n.ts";

const BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";
const WEBHOOK_SECRET = Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "";
const GEMINI_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const TG_API = `https://api.telegram.org/bot${BOT_TOKEN}`;
const REPORTS_BUCKET = "reports";

const admin = () =>
  createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

function ok() {
  // Telegram only cares that we return 200 — body is ignored.
  return new Response("ok", { status: 200 });
}

// ---------------------------------------------------------------------------
// Telegram Bot API helpers
// ---------------------------------------------------------------------------

async function tg(method: string, body: Record<string, unknown>) {
  const res = await fetch(`${TG_API}/${method}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  if (!res.ok) console.error(`telegram ${method} failed:`, await res.text());
  return res;
}

interface InlineKeyboard {
  inline_keyboard: Array<Array<{ text: string; callback_data: string }>>;
}

function sendMessage(chatId: number, text: string, keyboard?: InlineKeyboard) {
  return tg("sendMessage", {
    chat_id: chatId,
    text,
    parse_mode: "HTML",
    ...(keyboard ? { reply_markup: keyboard } : {}),
  });
}

function editMessageText(chatId: number, messageId: number, text: string, keyboard?: InlineKeyboard) {
  return tg("editMessageText", {
    chat_id: chatId,
    message_id: messageId,
    text,
    parse_mode: "HTML",
    reply_markup: keyboard ?? { inline_keyboard: [] },
  });
}

function answerCallbackQuery(id: string, text?: string) {
  return tg("answerCallbackQuery", { callback_query_id: id, ...(text ? { text } : {}) });
}

async function downloadPhoto(fileId: string): Promise<Uint8Array> {
  const fileRes = await fetch(`${TG_API}/getFile?file_id=${fileId}`);
  const fileData = await fileRes.json();
  const filePath = fileData?.result?.file_path;
  if (!filePath) throw new Error("could not resolve telegram file path");
  const fileUrl = `https://api.telegram.org/file/bot${BOT_TOKEN}/${filePath}`;
  const bytes = await fetch(fileUrl);
  return new Uint8Array(await bytes.arrayBuffer());
}

// ---------------------------------------------------------------------------
// AI photo verification (Gemini vision) — mirrors the in-app verify flow
// ---------------------------------------------------------------------------

// Chunked base64: spreading a multi-hundred-KB photo into String.fromCharCode
// arguments blows the call stack (RangeError) -- encode in 32 KB slices.
function toBase64(bytes: Uint8Array): string {
  let bin = "";
  const chunk = 0x8000;
  for (let i = 0; i < bytes.length; i += chunk) {
    bin += String.fromCharCode(...bytes.subarray(i, i + chunk));
  }
  return btoa(bin);
}

async function verifyPhoto(condition: string, jpeg: Uint8Array, isExcuse: boolean) {
  const base64 = toBase64(jpeg);
  const prompt = isExcuse
    ? `You are checking whether a user's excuse photo is a plausible reason they could not complete this task today: "${condition}".
Respond ONLY with JSON: {"approved": false, "excused": true or false, "explanation": "short reason, max 150 chars, same language as the condition"}`
    : `You are verifying photo proof for a habit-tracking app. The user needed to: "${condition}".
Look at the photo and decide if it genuinely satisfies that condition.
Respond ONLY with JSON: {"approved": true or false, "excused": false, "explanation": "short reason, max 150 chars, same language as the condition"}`;

  const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${GEMINI_KEY}`;
  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      contents: [{
        role: "user",
        parts: [
          { text: prompt },
          { inline_data: { mime_type: "image/jpeg", data: base64 } },
        ],
      }],
      generationConfig: { responseMimeType: "application/json", temperature: 0.2 },
    }),
  });
  if (!res.ok) throw new Error(`Gemini error: ${res.status} ${await res.text()}`);
  const data = await res.json();
  const raw = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "{}";
  const parsed = JSON.parse(raw);
  return {
    approved: Boolean(parsed.approved),
    excused: Boolean(parsed.excused),
    explanation: String(parsed.explanation ?? ""),
  };
}

// ---------------------------------------------------------------------------
// Command handlers
// ---------------------------------------------------------------------------

async function handleStart(chatId: number, username: string | undefined, code: string | undefined) {
  const db = admin();

  if (!code) {
    // No linked user to resolve a language for yet -- English default.
    await sendMessage(chatId, t("en", "startWelcome"));
    return;
  }

  const { data: linkCode } = await db
    .from("telegram_link_codes")
    .select("user_id, expires_at")
    .eq("code", code)
    .maybeSingle();

  if (!linkCode || new Date(linkCode.expires_at).getTime() < Date.now()) {
    await sendMessage(chatId, t("en", "startInvalidCode"));
    return;
  }

  const { data: linkedUser } = await db.from("users").select("language").eq("id", linkCode.user_id).maybeSingle();
  const lang = pickLang(linkedUser?.language);

  await db.from("telegram_links").upsert({
    user_id: linkCode.user_id,
    chat_id: chatId,
    username: username ?? null,
    linked_at: new Date().toISOString(),
  });
  await db.from("telegram_link_codes").delete().eq("code", code);

  await sendMessage(chatId, t(lang, "startLinked"));
}

async function handleHelp(chatId: number, lang: Lang) {
  await sendMessage(chatId, t(lang, "help"));
}

async function handleToday(chatId: number, userId: string, lang: Lang) {
  const db = admin();
  const { data: activities } = await db
    .from("activities")
    .select("title, type, frequency, streak_current, schedule_days")
    .eq("user_id", userId)
    .eq("status", "active")
    .order("created_at", { ascending: false })
    .limit(20);

  const tz = await userTimezone(db, userId);
  const todayDow = isoDowNow(tz);
  const todays = ((activities ?? []) as { title: string; type: string; frequency: string; streak_current: number; schedule_days: number[] | null }[])
    .filter((a) => a.frequency === "once" || isScheduledToday(a.schedule_days, todayDow));

  if (todays.length === 0) {
    await sendMessage(chatId, t(lang, "noTasksToday"));
    return;
  }

  const lines = todays.map((a) => {
    const streak = a.streak_current > 0 ? ` 🔥${a.streak_current}` : "";
    return `• ${a.title} <i>(${a.type})</i>${streak}`;
  });
  await sendMessage(chatId, `<b>${t(lang, "todayHeader")}</b>\n${lines.join("\n")}`);
}

async function handleNewTask(chatId: number, userId: string, title: string, lang: Lang) {
  const db = admin();
  const trimmed = title.trim();
  if (!trimmed) return;

  const { error } = await db.from("activities").insert({
    user_id: userId,
    title: trimmed.slice(0, 200),
    description: "",
    type: "task",
    frequency: "once",
    status: "active",
  });

  if (error) {
    console.error("insert activity failed:", error);
    await sendMessage(chatId, t(lang, "taskCreateFailed"));
    return;
  }

  await sendMessage(chatId, t(lang, "taskCreated", escapeHtml(trimmed)));
}

function escapeHtml(s: string) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// ISO weekday (1 = Monday ... 7 = Sunday) for "now" in the given IANA timezone.
// Matches Postgres extract(isodow) and activities.schedule_days.
function isoDowNow(tz: string): number {
  const wd = new Intl.DateTimeFormat("en-US", { timeZone: tz, weekday: "short" }).format(new Date());
  return ({ Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7 } as Record<string, number>)[wd] ?? 1;
}

async function userTimezone(db: ReturnType<typeof admin>, userId: string): Promise<string> {
  const { data } = await db.from("users").select("timezone").eq("id", userId).maybeSingle();
  return data?.timezone || "UTC";
}

// schedule_days empty/null = every day; otherwise only listed ISO weekdays.
function isScheduledToday(scheduleDays: number[] | null, todayDow: number): boolean {
  return !scheduleDays || scheduleDays.length === 0 || scheduleDays.includes(todayDow);
}

// ---------------------------------------------------------------------------
// Task management — /done, /delete, /stats (inline-keyboard driven)
// ---------------------------------------------------------------------------

async function pickActiveTask(chatId: number, userId: string, prompt: string, prefix: "done" | "delask", lang: Lang) {
  const db = admin();
  const { data: activities } = await db
    .from("activities")
    .select("id, title")
    .eq("user_id", userId)
    .eq("status", "active")
    .order("created_at", { ascending: false })
    .limit(10);

  const list = (activities ?? []) as { id: string; title: string }[];
  if (list.length === 0) {
    await sendMessage(chatId, t(lang, "noActiveTasks"));
    return;
  }

  const keyboard: InlineKeyboard = {
    inline_keyboard: list.map((a) => [{ text: a.title.slice(0, 60), callback_data: `${prefix}:${a.id}` }]),
  };
  await sendMessage(chatId, prompt, keyboard);
}

async function handleDoneList(chatId: number, userId: string, lang: Lang) {
  await pickActiveTask(chatId, userId, t(lang, "doneListPrompt"), "done", lang);
}

async function handleDoneCallback(chatId: number, messageId: number, userId: string, activityId: string, lang: Lang) {
  const db = admin();
  const { data: activity } = await db
    .from("activities")
    .select("id, title, user_id, frequency, status")
    .eq("id", activityId)
    .maybeSingle();

  if (!activity || activity.user_id !== userId || activity.status !== "active") {
    await editMessageText(chatId, messageId, t(lang, "taskUnavailable"));
    return;
  }

  // No ai_result here: defaults to 'not_applicable' (a plain check-in).
  // 'habit_done' is not allowed by the reports CHECK constraint and used to fail silently.
  const { error: reportError } = await db
    .from("reports")
    .insert({ activity_id: activity.id, comment: "Marked done via Telegram" });
  if (reportError) {
    console.error("done report insert failed:", reportError);
    await editMessageText(chatId, messageId, t(lang, "doneRecordFailed"));
    return;
  }
  if (activity.frequency === "once") {
    await db.from("activities").update({ status: "completed" }).eq("id", activity.id);
  }
  await editMessageText(chatId, messageId, t(lang, "taskDone", escapeHtml(activity.title)));
}

async function handleDeleteList(chatId: number, userId: string, lang: Lang) {
  await pickActiveTask(chatId, userId, t(lang, "deleteListPrompt"), "delask", lang);
}

async function handleDeleteAsk(chatId: number, messageId: number, userId: string, activityId: string, lang: Lang) {
  const db = admin();
  const { data: activity } = await db
    .from("activities")
    .select("id, title, user_id")
    .eq("id", activityId)
    .maybeSingle();

  if (!activity || activity.user_id !== userId) {
    await editMessageText(chatId, messageId, t(lang, "taskUnavailable"));
    return;
  }

  const keyboard: InlineKeyboard = {
    inline_keyboard: [[
      { text: t(lang, "deleteYes"), callback_data: `delyes:${activity.id}` },
      { text: t(lang, "cancel"), callback_data: "delno" },
    ]],
  };
  await editMessageText(chatId, messageId, t(lang, "deleteConfirmPrompt", escapeHtml(activity.title)), keyboard);
}

async function handleDeleteConfirm(chatId: number, messageId: number, userId: string, activityId: string, lang: Lang) {
  const db = admin();
  const { data: activity } = await db
    .from("activities")
    .select("id, title, user_id")
    .eq("id", activityId)
    .maybeSingle();

  if (!activity || activity.user_id !== userId) {
    await editMessageText(chatId, messageId, t(lang, "taskUnavailable"));
    return;
  }

  await db.from("activities").delete().eq("id", activity.id);
  await editMessageText(chatId, messageId, t(lang, "taskDeleted", escapeHtml(activity.title)));
}

async function handleStats(chatId: number, userId: string, lang: Lang) {
  const db = admin();
  const { data: activities } = await db
    .from("activities")
    .select("id, status, streak_current, streak_best")
    .eq("user_id", userId);

  const list = (activities ?? []) as { id: string; status: string; streak_current: number; streak_best: number }[];
  if (list.length === 0) {
    await sendMessage(chatId, t(lang, "noTasksYet"));
    return;
  }

  const active = list.filter((a) => a.status === "active").length;
  const completed = list.filter((a) => a.status === "completed").length;
  const failed = list.filter((a) => a.status === "failed").length;
  const bestStreak = list.reduce((m, a) => Math.max(m, a.streak_best ?? 0), 0);
  const currentStreak = list.reduce((m, a) => Math.max(m, a.streak_current ?? 0), 0);

  let reportLine = "";
  const ids = list.map((a) => a.id);
  if (ids.length > 0) {
    const { data: reports } = await db.from("reports").select("ai_result").in("activity_id", ids);
    const rows = (reports ?? []) as { ai_result: string }[];
    if (rows.length > 0) {
      const approved = rows.filter((r) => r.ai_result === "approved").length;
      const rejected = rows.filter((r) => r.ai_result === "rejected").length;
      const excused = rows.filter((r) => r.ai_result === "excused").length;
      reportLine = t(lang, "statsReportLine", String(approved), String(rejected), String(excused));
    }
  }

  await sendMessage(
    chatId,
    `<b>${t(lang, "statsHeader")}</b>\n` +
      t(lang, "statsBody", String(active), String(completed), String(failed), String(currentStreak), String(bestStreak)) +
      reportLine,
  );
}

// ---------------------------------------------------------------------------
// /history — recent photo reports
// ---------------------------------------------------------------------------

async function handleHistory(chatId: number, userId: string, lang: Lang) {
  const db = admin();
  const { data: activities } = await db.from("activities").select("id, title").eq("user_id", userId);
  const titleById = new Map((activities ?? []).map((a: { id: string; title: string }): [string, string] => [a.id, a.title]));
  const ids = [...titleById.keys()];

  if (ids.length === 0) {
    await sendMessage(chatId, t(lang, "noReportsYet"));
    return;
  }

  const { data: reports } = await db
    .from("reports")
    .select("activity_id, ai_result, ai_explanation, created_at")
    .in("activity_id", ids)
    .order("created_at", { ascending: false })
    .limit(5);

  const rows = (reports ?? []) as { activity_id: string; ai_result: string; ai_explanation: string | null; created_at: string }[];
  if (rows.length === 0) {
    await sendMessage(chatId, t(lang, "noReportsYet"));
    return;
  }

  const dateLocale = localeTag(lang);
  const lines = rows.map((r) => {
    const icon = r.ai_result === "approved" ? "✅" : r.ai_result === "rejected" ? "❌" : r.ai_result === "excused" ? "🙏" : "📝";
    const title = escapeHtml(titleById.get(r.activity_id) ?? t(lang, "taskFallbackTitle"));
    const when = new Date(r.created_at).toLocaleDateString(dateLocale, { month: "short", day: "numeric" });
    const note = r.ai_explanation ? ` — ${escapeHtml(r.ai_explanation)}` : "";
    return `${icon} <b>${title}</b> <i>(${when})</i>${note}`;
  });
  await sendMessage(chatId, `<b>${t(lang, "recentReportsHeader")}</b>\n${lines.join("\n")}`);
}

interface ActivityRow {
  id: string;
  title: string;
  type: string;
  condition: string | null;
  frequency: string;
}

async function handlePhoto(chatId: number, userId: string, fileId: string, caption: string | undefined, lang: Lang) {
  const db = admin();

  // Any active task accepts photo proof (mirrors the in-app flow, which
  // verifies every type against condition or title -- not just challenges).
  const { data: candidates } = await db
    .from("activities")
    .select("id, title, type, condition, frequency")
    .eq("user_id", userId)
    .eq("status", "active")
    .order("created_at", { ascending: false })
    .limit(50);

  const list = (candidates ?? []) as ActivityRow[];
  if (list.length === 0) {
    await sendMessage(chatId, t(lang, "noActiveTasksCreate"));
    return;
  }

  let activity: ActivityRow | undefined;
  if (caption?.trim()) {
    const needle = caption.trim().toLowerCase();
    activity = list.find((a) => a.title.toLowerCase().includes(needle));
    if (!activity) {
      const listText = list.map((a) => `• ${a.title}`).join("\n");
      await sendMessage(chatId, t(lang, "taskNotFoundByCaption", escapeHtml(caption.trim()), listText));
      return;
    }
  } else if (list.length === 1) {
    activity = list[0];
  } else {
    // Remember the photo and let the user tap which challenge it's for.
    await db.from("telegram_links").update({ pending_photo: { file_id: fileId, caption: caption ?? null } }).eq("chat_id", chatId);
    const keyboard: InlineKeyboard = {
      inline_keyboard: list.map((a) => [{ text: a.title.slice(0, 60), callback_data: `photopick:${a.id}` }]),
    };
    await sendMessage(chatId, t(lang, "photoPickPrompt"), keyboard);
    return;
  }

  await sendMessage(chatId, t(lang, "verifying", escapeHtml(activity.title)));
  await runVerification(chatId, activity, fileId, caption, lang);
}

async function handlePhotoPick(chatId: number, messageId: number, userId: string, activityId: string, lang: Lang) {
  const db = admin();
  const { data: link } = await db.from("telegram_links").select("pending_photo").eq("chat_id", chatId).maybeSingle();
  const pending = link?.pending_photo as { file_id: string; caption: string | null } | null;
  if (!pending?.file_id) {
    await editMessageText(chatId, messageId, t(lang, "photoPromptExpired"));
    return;
  }

  const { data: activity } = await db
    .from("activities")
    .select("id, title, type, condition, frequency, status, user_id")
    .eq("id", activityId)
    .maybeSingle();

  if (!activity || activity.user_id !== userId || activity.status !== "active") {
    await editMessageText(chatId, messageId, t(lang, "taskUnavailableResend"));
    return;
  }

  await db.from("telegram_links").update({ pending_photo: null }).eq("chat_id", chatId);
  await editMessageText(chatId, messageId, t(lang, "verifying", escapeHtml(activity.title)));
  await runVerification(chatId, activity, pending.file_id, pending.caption ?? undefined, lang);
}

async function runVerification(chatId: number, activity: ActivityRow, fileId: string, caption: string | undefined, lang: Lang) {
  const db = admin();
  try {
    const jpeg = await downloadPhoto(fileId);
    const path = `${activity.id}/${crypto.randomUUID()}.jpg`;
    const { error: uploadError } = await db.storage
      .from(REPORTS_BUCKET)
      .upload(path, jpeg, { contentType: "image/jpeg" });
    if (uploadError) throw uploadError;

    const { data: pub } = db.storage.from(REPORTS_BUCKET).getPublicUrl(path);
    const photoURL = pub.publicUrl;

    const { data: report, error: reportError } = await db
      .from("reports")
      .insert({ activity_id: activity.id, photo_url: photoURL, comment: caption ?? null })
      .select()
      .single();
    if (reportError) throw reportError;

    // Verify every task: against its photo condition if set, otherwise the
    // title -- same rule as the in-app camera flow.
    const condition = activity.condition?.trim() || activity.title;
    if (condition) {
      const ai = await verifyPhoto(condition, jpeg, false);
      const result = ai.approved ? "approved" : ai.excused ? "excused" : "rejected";

      await db.from("reports")
        .update({ ai_result: result, ai_explanation: ai.explanation })
        .eq("id", report.id);

      if (result === "approved" && activity.frequency === "once") {
        await db.from("activities").update({ status: "completed" }).eq("id", activity.id);
      }

      const icon = result === "approved" ? "✅" : result === "excused" ? "🙏" : "❌";
      await sendMessage(chatId, `${icon} <b>${escapeHtml(activity.title)}</b>\n${escapeHtml(ai.explanation)}`);
    } else {
      await sendMessage(chatId, t(lang, "proofSubmitted", escapeHtml(activity.title)));
    }
  } catch (err) {
    console.error("photo handling failed:", err);
    await sendMessage(chatId, t(lang, "verifyError"));
  }
}

// ---------------------------------------------------------------------------
// Inline-keyboard callback routing (/done, /delete, photo picker)
// ---------------------------------------------------------------------------

async function handleCallbackQuery(callback: any) {
  const id: string | undefined = callback?.id;
  const chatId: number | undefined = callback?.message?.chat?.id;
  const messageId: number | undefined = callback?.message?.message_id;
  const data: string | undefined = callback?.data;

  if (!id) return;
  if (!chatId || !messageId || !data) {
    await answerCallbackQuery(id);
    return;
  }

  const db = admin();
  const { data: link } = await db.from("telegram_links").select("user_id").eq("chat_id", chatId).maybeSingle();
  if (!link) {
    await answerCallbackQuery(id, "This chat isn't linked anymore.");
    return;
  }
  const { data: linkedUser } = await db.from("users").select("language").eq("id", link.user_id).maybeSingle();
  const lang = pickLang(linkedUser?.language);

  const sep = data.indexOf(":");
  const action = sep === -1 ? data : data.slice(0, sep);
  const arg = sep === -1 ? "" : data.slice(sep + 1);

  try {
    switch (action) {
      case "done":
        await handleDoneCallback(chatId, messageId, link.user_id, arg, lang);
        break;
      case "delask":
        await handleDeleteAsk(chatId, messageId, link.user_id, arg, lang);
        break;
      case "delyes":
        await handleDeleteConfirm(chatId, messageId, link.user_id, arg, lang);
        break;
      case "delno":
        await editMessageText(chatId, messageId, t(lang, "deleteCancelled"));
        break;
      case "photopick":
        await handlePhotoPick(chatId, messageId, link.user_id, arg, lang);
        break;
    }
  } finally {
    await answerCallbackQuery(id);
  }
}

// ---------------------------------------------------------------------------
// Webhook entrypoint
// ---------------------------------------------------------------------------

serve(async (req) => {
  if (req.method !== "POST") return ok();

  // Reject anything that isn't Telegram (the secret token is set via setWebhook
  // and echoed back on every request — see header link in the file comment).
  if (WEBHOOK_SECRET && req.headers.get("X-Telegram-Bot-Api-Secret-Token") !== WEBHOOK_SECRET) {
    return new Response("forbidden", { status: 403 });
  }

  let update: any;
  try {
    update = await req.json();
  } catch {
    return ok();
  }

  if (update?.callback_query) {
    try {
      await handleCallbackQuery(update.callback_query);
    } catch (err) {
      console.error("telegram-webhook callback error:", err);
    }
    return ok();
  }

  const message = update?.message;
  if (!message?.chat?.id) return ok();

  const chatId: number = message.chat.id;
  const username: string | undefined = message.from?.username;
  const text: string | undefined = message.text;
  const caption: string | undefined = message.caption;
  const photos: Array<{ file_id: string }> | undefined = message.photo;

  let lang: Lang = "en";
  try {
    // "/start" works before linking; everything else requires a linked account.
    if (text?.startsWith("/start")) {
      const code = text.split(/\s+/)[1];
      await handleStart(chatId, username, code);
      return ok();
    }

    const db = admin();
    const { data: link } = await db
      .from("telegram_links")
      .select("user_id")
      .eq("chat_id", chatId)
      .maybeSingle();

    if (!link) {
      // No linked user to resolve a language for -- English default.
      await sendMessage(chatId, "This chat isn't linked to a reInspire account yet. Open the app → Profile → Telegram bot to get a linking code, then send <code>/start YOUR_CODE</code>.");
      return ok();
    }

    const { data: linkedUser } = await db.from("users").select("language").eq("id", link.user_id).maybeSingle();
    lang = pickLang(linkedUser?.language);

    if (photos && photos.length > 0) {
      const best = photos[photos.length - 1]; // largest resolution is last
      await handlePhoto(chatId, link.user_id, best.file_id, caption, lang);
    } else if (text === "/help") {
      await handleHelp(chatId, lang);
    } else if (text === "/today" || text === "/tasks") {
      await handleToday(chatId, link.user_id, lang);
    } else if (text === "/done") {
      await handleDoneList(chatId, link.user_id, lang);
    } else if (text === "/delete" || text === "/remove") {
      await handleDeleteList(chatId, link.user_id, lang);
    } else if (text === "/history") {
      await handleHistory(chatId, link.user_id, lang);
    } else if (text === "/stats") {
      await handleStats(chatId, link.user_id, lang);
    } else if (text && text.trim()) {
      await handleNewTask(chatId, link.user_id, text, lang);
    }
  } catch (err) {
    console.error("telegram-webhook error:", err);
    try { await sendMessage(chatId, t(lang, "genericError")); } catch { /* ignore */ }
  }

  return ok();
});
