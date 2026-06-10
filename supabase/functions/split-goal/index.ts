// Edge Function: split-goal
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { checkRateLimit, CORS_HEADERS } from "../_shared/rateLimiter.ts";

const GEMINI_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent";

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  const rateResult = await checkRateLimit(req, "coach-group");
  if (rateResult instanceof Response) return rateResult;

  try {
    const { goalTitle, goalDescription, targetValue, deadlineDays } = await req.json();

    const targetNote = targetValue ? `Target value: ${targetValue}.` : "";
    const deadlineNote = deadlineDays ? `Deadline: ${deadlineDays} days from now.` : "";

    const prompt = `You are a productivity expert helping a user break down a goal in a habit-tracking app.
Goal: "${goalTitle}"
Description: "${goalDescription || "none"}"
${targetNote} ${deadlineNote}

Break this into 3-6 concrete, actionable subtasks. Each should be completable in 1-5 days.
Respond ONLY with valid JSON (no markdown):
{
  "subtasks": [
    { "title": "subtask title (max 60 chars)", "estimatedDays": 1-5 },
    ...
  ]
}`;

    const res = await fetch(`${GEMINI_URL}?key=${GEMINI_KEY}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [{ parts: [{ text: prompt }] }],
        generationConfig: { temperature: 0.6, maxOutputTokens: 400 },
      }),
    });

    if (!res.ok) throw new Error(`Gemini error: ${res.status}`);
    const data = await res.json();
    const raw = data.candidates?.[0]?.content?.parts?.[0]?.text ?? "{}";
    const cleaned = raw.replace(/```json?\n?/g, "").replace(/```/g, "").trim();
    const parsed = JSON.parse(cleaned);

    parsed.subtasks = (parsed.subtasks ?? []).slice(0, 6);

    return new Response(JSON.stringify({ ...parsed, remaining: rateResult.remaining }), {
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (e) {
    return new Response(
      JSON.stringify({ subtasks: [], error: String(e) }),
      { headers: { ...CORS_HEADERS, "Content-Type": "application/json" } }
    );
  }
});
