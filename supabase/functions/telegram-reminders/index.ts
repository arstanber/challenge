// Edge Function: telegram-reminders
// Scheduled (via pg_cron + pg_net, see migration 20260608c_telegram_reminders_cron.sql)
// to run once a day. Sends every linked Telegram user a short digest of the
// active tasks they haven't logged a report for yet today — nudging them
// before they lose their streak.
//
// Day boundaries are per-user (users.timezone, IANA identifier upserted by the
// app); tasks are filtered by activities.schedule_days (ISO 1=Mon..7=Sun,
// NULL/empty = every day) and once-tasks with a deadline beyond tomorrow are
// not nagged about.
//
// Internal/service-only: invoked by pg_cron with no user-facing auth, same
// pattern as telegram-notify (verify_jwt = false, service_role DB access only).

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { pickLang } from "../_shared/i18n.ts";

const BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";
const TG_API = `https://api.telegram.org/bot${BOT_TOKEN}`;

const admin = () =>
  createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

function sendMessage(chatId: number, text: string) {
  return fetch(`${TG_API}/sendMessage`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ chat_id: chatId, text, parse_mode: "HTML" }),
  });
}

function escapeHtml(s: string) {
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
}

// "YYYY-MM-DD" of the given instant in the given IANA timezone (en-CA gives ISO order).
function localDateStr(date: Date, tz: string): string {
  return new Intl.DateTimeFormat("en-CA", { timeZone: tz }).format(date);
}

// ISO weekday (1 = Monday ... 7 = Sunday) of "now" in the given timezone.
// Matches Postgres extract(isodow) and activities.schedule_days.
function isoDowNow(tz: string): number {
  const wd = new Intl.DateTimeFormat("en-US", { timeZone: tz, weekday: "short" }).format(new Date());
  return ({ Mon: 1, Tue: 2, Wed: 3, Thu: 4, Fri: 5, Sat: 6, Sun: 7 } as Record<string, number>)[wd] ?? 1;
}

interface ActivityRow {
  id: string;
  title: string;
  type: string;
  frequency: string;
  deadline: string | null;
  schedule_days: number[] | null;
  streak_current: number;
}

serve(async (req) => {
  if (req.method !== "POST") return new Response("ok", { status: 200 });

  const db = admin();
  const now = new Date();
  // Wide net: pull the last 48h of reports per user, then bucket by the
  // user's local date. Avoids computing the UTC instant of local midnight.
  const lookback = new Date(now.getTime() - 48 * 3600 * 1000);

  const { data: links } = await db.from("telegram_links").select("user_id, chat_id");
  let sent = 0;

  for (const link of (links ?? []) as { user_id: string; chat_id: number }[]) {
    try {
      const { data: userRow } = await db
        .from("users")
        .select("timezone, language")
        .eq("id", link.user_id)
        .maybeSingle();
      const tz = userRow?.timezone || "UTC";
      const lang = pickLang(userRow?.language);
      const today = localDateStr(now, tz);
      const todayDow = isoDowNow(tz);

      const { data: activities } = await db
        .from("activities")
        .select("id, title, type, frequency, deadline, schedule_days, streak_current")
        .eq("user_id", link.user_id)
        .eq("status", "active")
        .order("created_at", { ascending: false })
        .limit(50);

      const list = ((activities ?? []) as ActivityRow[]).filter((a) => {
        if (a.frequency === "once") {
          // Don't nag about one-offs due later than tomorrow.
          if (!a.deadline) return true;
          const deadlineLocal = localDateStr(new Date(a.deadline), tz);
          const tomorrow = localDateStr(new Date(now.getTime() + 24 * 3600 * 1000), tz);
          return deadlineLocal <= tomorrow;
        }
        // Recurring: only on its scheduled days (empty/null = every day).
        return !a.schedule_days || a.schedule_days.length === 0 || a.schedule_days.includes(todayDow);
      });
      if (list.length === 0) continue;

      const ids = list.map((a) => a.id);
      const { data: recent } = await db
        .from("reports")
        .select("activity_id, created_at")
        .in("activity_id", ids)
        .gte("created_at", lookback.toISOString());

      const doneIds = new Set(
        ((recent ?? []) as { activity_id: string; created_at: string }[])
          .filter((r) => localDateStr(new Date(r.created_at), tz) === today)
          .map((r) => r.activity_id),
      );
      const pending = list.filter((a) => !doneIds.has(a.id));
      if (pending.length === 0) continue;

      const lines = pending.slice(0, 8).map((a) => {
        const streak = a.streak_current > 0 ? ` 🔥${a.streak_current}` : "";
        return `• ${escapeHtml(a.title)}${streak}`;
      });

      const text = lang === "ru"
        ? "<b>⏰ Не забудь сегодня</b>\n" +
          `${lines.join("\n")}\n\n` +
          "Отправь сюда фото или сообщение, чтобы отметить, или открой приложение."
        : "<b>⏰ Don't forget today</b>\n" +
          `${lines.join("\n")}\n\n` +
          "Send a photo or message here to log it, or open the app.";
      await sendMessage(link.chat_id, text);
      sent++;
    } catch (err) {
      console.error(`reminder failed for user ${link.user_id}:`, err);
    }
  }

  return new Response(JSON.stringify({ sent }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});
