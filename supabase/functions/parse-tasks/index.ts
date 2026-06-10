import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { checkRateLimit, CORS_HEADERS } from "../_shared/rateLimiter.ts";

const GEMINI_MODEL = "gemini-2.5-flash";

const SYSTEM_PROMPT = `You convert a user's spoken brain-dump into a structured list of actionable to-dos.
The user may speak English or Russian and may run multiple tasks together with
"and", "then", commas, or filler phrases ("I need to", "remember to", "let me", etc.).

Rules:
- Output one entry per distinct task. Deduplicate near-identical items.
- Each title should be a short, imperative phrase in the same language the user spoke,
  capitalised, with no leading filler ("I need to ...", "Remember to ...") and no trailing
  punctuation. Keep it under ~60 characters.
- Assign exactly one category, from this fixed list:
  SPORT, HEALTH, FOOD, STUDY, WORK, FINANCE, HOME, MENTAL HEALTH, SOCIAL, OTHER.
- Assign a type:
    - "habit" for recurring physical / health activities (run, gym, hydrate, sleep).
    - "goal"  for learning / mental-health objectives (study X, meditate, read a book).
    - "task"  for everything else (one-shot to-dos like "pay the rent").
- If the transcript is empty or pure filler, return an empty tasks array.`;

const RESPONSE_SCHEMA = {
  type: "object",
  properties: {
    tasks: {
      type: "array",
      items: {
        type: "object",
        properties: {
          title:    { type: "string" },
          category: {
            type: "string",
            enum: ["SPORT", "HEALTH", "FOOD", "STUDY", "WORK", "FINANCE", "HOME", "MENTAL HEALTH", "SOCIAL", "OTHER"],
          },
          type: {
            type: "string",
            enum: ["habit", "goal", "task"],
          },
        },
        required: ["title", "category", "type"],
      },
    },
  },
  required: ["tasks"],
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  // Rate limit: parse-tasks is the entry point for the full voice flow.
  // parse-schedule and categorize run as helper steps in the same flow and are not charged separately.
  const rateResult = await checkRateLimit(req, "parse-tasks-group");
  if (rateResult instanceof Response) return rateResult;

  try {
    const apiKey = Deno.env.get("GEMINI_API_KEY");
    if (!apiKey) {
      return new Response(JSON.stringify({ error: "GEMINI_API_KEY secret not set" }), {
        status: 500,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const { transcript } = await req.json();
    if (!transcript || typeof transcript !== "string" || !transcript.trim()) {
      return new Response(JSON.stringify({ tasks: [] }), {
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${apiKey}`;
    const body = {
      systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
      contents: [{ role: "user", parts: [{ text: transcript.trim() }] }],
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: RESPONSE_SCHEMA,
        temperature: 0.2,
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
        status: 502,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      });
    }

    const geminiData = await geminiRes.json();
    const jsonText = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text ?? '{"tasks":[]}';
    const parsed = JSON.parse(jsonText);

    return new Response(JSON.stringify({ ...parsed, remaining: rateResult.remaining }), {
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
});
