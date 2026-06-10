// Edge Function: telegram-notify
// Internal helper other server-side flows call to push a message to a user's
// linked Telegram chat (streak nudges, AI-verification results, reminders, ...).
// Not exposed to clients — only callable with the service_role key, e.g.:
//
//   await fetch(`${SUPABASE_URL}/functions/v1/telegram-notify`, {
//     method: "POST",
//     headers: { Authorization: `Bearer ${SUPABASE_SERVICE_ROLE_KEY}`, "Content-Type": "application/json" },
//     body: JSON.stringify({ userId, text: "🔥 Don't break your streak — finish today's task!" }),
//   });
//
// Returns { sent: true } if the user has linked Telegram, { sent: false } otherwise
// (e.g. so a caller can fall back to a push notification).

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";
const TG_API = `https://api.telegram.org/bot${BOT_TOKEN}`;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

const admin = () =>
  createClient(Deno.env.get("SUPABASE_URL")!, SERVICE_ROLE_KEY);

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  // Only the service_role key may call this — it's an internal, server-to-server hop.
  const authHeader = req.headers.get("Authorization") ?? "";
  if (authHeader !== `Bearer ${SERVICE_ROLE_KEY}`) {
    return json({ error: "Unauthorized" }, 401);
  }

  try {
    const { userId, text } = await req.json();
    if (!userId || !text) return json({ error: "userId and text are required" }, 400);

    const db = admin();
    const { data: link } = await db
      .from("telegram_links")
      .select("chat_id")
      .eq("user_id", userId)
      .maybeSingle();

    if (!link) return json({ sent: false });

    const res = await fetch(`${TG_API}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ chat_id: link.chat_id, text, parse_mode: "HTML" }),
    });
    if (!res.ok) {
      console.error("telegram sendMessage failed:", await res.text());
      return json({ sent: false, error: "telegram_send_failed" }, 502);
    }

    return json({ sent: true });
  } catch (err) {
    return json({ error: String(err) }, 500);
  }
});
