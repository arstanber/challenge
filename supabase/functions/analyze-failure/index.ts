// Edge Function: analyze-failure
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
    const { activityTitle, activityType, streakBefore, userReason, language } = await req.json();
    lang = pickLang(language);

    const userNote = userReason ? `The user says: "${userReason}"` : "The user didn't provide a reason.";
    const streakNote = streakBefore > 0 ? `This broke their ${streakBefore}-day streak.` : "";
    const langNote = lang === "ru" ? "Respond in Russian." : "Respond in English.";

    const prompt = `You are a supportive productivity coach for a habit-tracking app called "reInspire".
A user failed their ${activityType} activity: "${activityTitle}". ${streakNote}
${userNote}
${langNote}

Respond ONLY with valid JSON (no markdown):
{
  "reason": "empathetic 1-2 sentence analysis of likely cause (max 150 chars)",
  "suggestion": "specific actionable next step to get back on track (max 150 chars)",
  "reschedule": true or false
}`;

    const res = await fetch(`${GEMINI_URL}?key=${GEMINI_KEY}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.5, maxOutputTokens: 200 },
      }),
    });

    if (!res.ok) throw new Error(`Gemini error: ${res.status}`);
    const data = await res.json();
    const raw = data.candidates?.[0]?.content?.parts?.[0]?.text ?? "{}";
    const cleaned = raw.replace(/```json?\n?/g, "").replace(/```/g, "").trim();
    const parsed = JSON.parse(cleaned);

    return new Response(JSON.stringify({ ...parsed, remaining: rateResult.remaining }), {
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (e) {
    const fallback = lang === "ru"
      ? { reason: "Бывает -- не будь к себе слишком строг.", suggestion: "Попробуй завтра с меньшего шага." }
      : { reason: "Life happens — don't be too hard on yourself.", suggestion: "Try again tomorrow with a smaller step." };
    return new Response(
      JSON.stringify({ ...fallback, reschedule: true, error: String(e) }),
      { headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
    );
  }
});
