import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { verifyAuth, CORS_HEADERS } from "../_shared/rateLimiter.ts";

const GEMINI_MODEL = "gemini-2.5-flash";

const SYSTEM_PROMPT = `You assign a single category to each to-do title.
Titles may be in English or Russian.
For every input title, return exactly one category from this fixed list:
SPORT, HEALTH, FOOD, STUDY, WORK, FINANCE, HOME, MENTAL HEALTH, SOCIAL, OTHER.

Return the categories array in the SAME ORDER as the input titles, one category per title.
Use OTHER only when nothing else fits.`;

const RESPONSE_SCHEMA = {
  type: "object",
  properties: {
    categories: {
      type: "array",
      items: {
        type: "string",
        enum: ["SPORT", "HEALTH", "FOOD", "STUDY", "WORK", "FINANCE", "HOME", "MENTAL HEALTH", "SOCIAL", "OTHER"],
      },
    },
  },
  required: ["categories"],
};

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  // JWT-only check: categorize is a helper step in the voice flow;
  // the usage counter is already incremented by parse-tasks.
  const authResult = await verifyAuth(req);
  if (authResult instanceof Response) return authResult;

  try {
    const apiKey = Deno.env.get("GEMINI_API_KEY");
    if (!apiKey) {
      return new Response(JSON.stringify({ error: "GEMINI_API_KEY secret not set" }), {
        status: 500,
        headers: { "Content-Type": "application/json" },
      });
    }

    const { titles } = await req.json();
    if (!Array.isArray(titles) || titles.length === 0) {
      return new Response(JSON.stringify({ categories: [] }), {
        headers: { "Content-Type": "application/json" },
      });
    }

    const numbered = titles.map((t: string, i: number) => `${i + 1}. ${t}`).join("\n");

    const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${apiKey}`;
    const body = {
      systemInstruction: { parts: [{ text: SYSTEM_PROMPT }] },
      contents: [{ role: "user", parts: [{ text: numbered }] }],
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
        status: 502,
        headers: { "Content-Type": "application/json" },
      });
    }

    const geminiData = await geminiRes.json();
    const jsonText = geminiData?.candidates?.[0]?.content?.parts?.[0]?.text ?? '{"categories":[]}';
    const parsed = JSON.parse(jsonText);

    return new Response(JSON.stringify(parsed), {
      headers: { "Content-Type": "application/json" },
    });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }
});
