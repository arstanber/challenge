// Edge Function: morning-brief
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { checkRateLimit, CORS_HEADERS } from "../_shared/rateLimiter.ts";
import { pickLang } from "../_shared/i18n.ts";

const GEMINI_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent";

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  const rateResult = await checkRateLimit(req, "coach-group");
  if (rateResult instanceof Response) return rateResult;

  let lang: "en" | "ru" = "en";
  try {
    const { streakCurrent, todayTasks, language } = await req.json();
    lang = pickLang(language);
    // Guard against a missing / non-array body so .slice/.includes can't throw.
    const tasks: string[] = Array.isArray(todayTasks)
      ? todayTasks.filter((t: unknown): t is string => typeof t === "string")
      : [];

    const taskList = tasks.slice(0, 5).join(", ") || "no tasks set yet";
    const streakText = streakCurrent > 0 ? `They're on a ${streakCurrent}-day streak.` : "They don't have a streak yet.";
    const langNote = lang === "ru" ? "Respond in Russian." : "Respond in English.";

    const prompt = `You are an enthusiastic productivity coach for a habit-tracking app called "reInspire".
Write a short morning brief for a user. ${streakText}
Today's activities: ${taskList}
${langNote}

Respond ONLY with valid JSON in this exact format (no markdown):
{
  "greeting": "one upbeat sentence acknowledging their streak or motivating them to start one (max 120 chars)",
  "topTasks": ["task1", "task2", "task3"],
  "motivationTip": "one actionable tip for today (max 100 chars)"
}`;

    const res = await fetch(`${GEMINI_URL}?key=${GEMINI_KEY}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.7, maxOutputTokens: 300 },
      }),
    });

    if (!res.ok) throw new Error(`Gemini error: ${res.status}`);
    const data = await res.json();
    const raw = data.candidates?.[0]?.content?.parts?.[0]?.text ?? "{}";
    const cleaned = raw.replace(/```json?\n?/g, "").replace(/```/g, "").trim();
    const parsed = JSON.parse(cleaned);

    parsed.topTasks = (Array.isArray(parsed.topTasks) ? parsed.topTasks as string[] : [])
      .filter((t: string) => tasks.includes(t))
      .slice(0, 3);
    if (parsed.topTasks.length === 0) parsed.topTasks = tasks.slice(0, 3);

    return new Response(JSON.stringify({ ...parsed, remaining: rateResult.remaining }), {
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (e) {
    const fallback = lang === "ru"
      ? { greeting: "Сделаем этот день продуктивным!", motivationTip: "Начни с самой сложной задачи." }
      : { greeting: "Let's make today count!", motivationTip: "Start with your hardest task first." };
    return new Response(
      JSON.stringify({ ...fallback, topTasks: [], error: String(e) }),
      { headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
    );
  }
});
