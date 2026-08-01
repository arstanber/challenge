import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { checkRateLimit, CORS_HEADERS } from "../_shared/rateLimiter.ts";
import { type Lang, pickLang, respondIn } from "../_shared/i18n.ts";

const GEMINI_KEY = Deno.env.get("GEMINI_API_KEY") ?? "";
const GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent";

type ChatMessage = { role: "user" | "assistant"; content: string };

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const rateResult = await checkRateLimit(req, "ai-chat");
  if (rateResult instanceof Response) return rateResult;

  try {
    const body = await req.json();
    const lang: Lang = pickLang(body.language);
    const messages = sanitizeMessages(body.messages);
    if (messages.length === 0 || messages.at(-1)?.role !== "user") {
      return json({ error: "invalid_messages", remaining: rateResult.remaining }, 400);
    }

    const tasks = Array.isArray(body.todayTasks)
      ? body.todayTasks.filter((item: unknown): item is string => typeof item === "string").slice(0, 20)
      : [];
    const streak = Number.isFinite(body.streakCurrent) ? Math.max(0, Math.floor(body.streakCurrent)) : 0;
    const taskContext = tasks.length > 0 ? tasks.join(", ") : "No tasks scheduled for today";

    const systemPrompt = `You are the user's personal AI coach inside reInspire, a habit and goal app.
Be warm, practical, concise, and honest. Help with the user's real goals, motivation, planning, habits, and reflection.
Today's tasks: ${taskContext}
Current streak: ${streak} days.
${respondIn(lang)}
Use the task context naturally when relevant. Prefer one clear next action. Do not claim that you completed, moved, edited, or verified a task. Do not provide medical diagnosis or shame the user. Keep replies under 180 words.`;

    const contents = messages.map((message) => ({
      role: message.role === "assistant" ? "model" : "user",
      parts: [{ text: message.content }],
    }));
    contents[0].parts[0].text = `${systemPrompt}\n\nUser message:\n${contents[0].parts[0].text}`;

    const response = await fetch(`${GEMINI_URL}?key=${GEMINI_KEY}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents,
        generationConfig: {
          temperature: 0.65,
          maxOutputTokens: 420,
          thinkingConfig: { thinkingBudget: 0 },
        },
      }),
    });

    if (!response.ok) throw new Error(`Gemini error: ${response.status}`);
    const data = await response.json();
    const reply = data.candidates?.[0]?.content?.parts?.[0]?.text?.trim();
    if (!reply) throw new Error("Empty model response");

    return json({ reply, remaining: rateResult.remaining });
  } catch (error) {
    console.error("ai-chat failed:", error);
    return json({ error: "chat_unavailable", remaining: rateResult.remaining }, 500);
  }
});

function sanitizeMessages(value: unknown): ChatMessage[] {
  if (!Array.isArray(value)) return [];
  return value
    .filter((message): message is Record<string, unknown> => typeof message === "object" && message !== null)
    .filter((message) => message.role === "user" || message.role === "assistant")
    .filter((message) => typeof message.content === "string" && message.content.trim().length > 0)
    .slice(-12)
    .map((message) => ({
      role: message.role as ChatMessage["role"],
      content: (message.content as string).trim().slice(0, 1_000),
    }));
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}
