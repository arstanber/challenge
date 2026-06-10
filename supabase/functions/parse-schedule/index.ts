import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { verifyAuth, CORS_HEADERS } from "../_shared/rateLimiter.ts";

const GEMINI_MODEL = "gemini-2.5-flash";

const SYSTEM_PROMPT = `You extract schedule information from a spoken instruction and map it to a numbered task list.

Tasks are numbered starting at 0. The user may refer to tasks by position ("first"/"первое" → 0, "second"/"второе" → 1, etc.),
by partial title, or with collective words ("all"/"все", "the rest"/"остальные" — apply to all unmentioned tasks).

For EACH task in the list return one entry. Use the task's array index as "index".

Fields to extract:
- scheduleLabel: short human-readable string in the user's language, e.g. "Every day 7 AM" / "Каждый день в 7:00"
- durationLabel: short string like "2 weeks" / "3 дня", or null if not mentioned
- frequency: "once" | "daily" | "weekly"
- hour: integer 0–23 (24-h) or null
- minute: integer 0–59 or null
- deadlineDays: number of days from today as integer, or null

Rules:
- "2 недели" = 14 days, "месяц" = 30 days, "неделя" = 7 days, "3 дня" = 3 days
- "утром" = hour 7, "вечером" = hour 19, "днём" = hour 13, "ночью" = hour 22
- "каждый день" = daily, "раз в неделю" = weekly, "один раз"/"once"/"сегодня" = once
- If no information is given for a task, default: frequency="once", everything else null
- Keep labels in the same language as the user's input`;

const RESPONSE_SCHEMA = {
  type: "object",
  properties: {
    schedules: {
      type: "array",
      items: {
        type: "object",
        properties: {
          index:         { type: "integer" },
          scheduleLabel: { type: "string" },
          durationLabel: { type: "string" },
          frequency:     { type: "string", enum: ["once", "daily", "weekly"] },
          hour:          { type: "integer" },
          minute:        { type: "integer" },
          deadlineDays:  { type: "integer" },
        },
        required: ["index", "scheduleLabel", "frequency"],
      },
    },
  },
  required: ["schedules"],
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  // JWT-only check: parse-schedule is a helper step in the voice flow;
  // the usage counter is already incremented by parse-tasks.
  const authResult = await verifyAuth(req);
  if (authResult instanceof Response) return authResult;

  try {
    const apiKey = Deno.env.get("GEMINI_API_KEY");
    if (!apiKey) {
      return new Response(JSON.stringify({ error: "GEMINI_API_KEY secret not set" }), {
        status: 500, headers: { "Content-Type": "application/json" },
      });
    }

    const { tasks, transcript } = await req.json();
    if (!tasks?.length || !transcript?.trim()) {
      return new Response(JSON.stringify({ schedules: [] }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    const taskList = (tasks as string[])
      .map((t: string, i: number) => `${i}. ${t}`)
      .join("\n");

    const userMessage = `Tasks:\n${taskList}\n\nSchedule instruction: "${transcript.trim()}"`;

    const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${apiKey}`;
    const body = {
      systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
      contents: [{ role: "user", parts: [{ text: userMessage }] }],
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: RESPONSE_SCHEMA,
        temperature: 0.1,
      },
    };

    const geminiRes = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });

    if (!geminiRes.ok) {
      const errText = await geminiRes.text();
      return new Response(JSON.stringify({ error: `Gemini error: ${errText}` }), {
        status: 502, headers: { "Content-Type": "application/json" },
      });
    }

    const geminiData = await geminiRes.json();
    const jsonText = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text ?? '{"schedules":[]}';
    const parsed = JSON.parse(jsonText);

    return new Response(JSON.stringify(parsed), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500, headers: { "Content-Type": "application/json" },
    });
  }
});
