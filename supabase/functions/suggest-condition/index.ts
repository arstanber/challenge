import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

// Suggests a photo-proof condition for a task from its title/description, so the
// user does not have to write "what should I photograph" themselves. Fast model,
// authenticated, monthly-quota limited (suggest-condition bucket).
const MODEL = "claude-haiku-4-5-20251001";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  try {
    const body = await req.json();
    const title = String(body.title ?? "").trim();
    const description = String(body.description ?? "").trim();
    if (!title) return json({ error: "Missing title" }, 400);

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;

    // Authenticate -- user id comes from the verified JWT.
    const authHeader = req.headers.get("Authorization") ?? "";
    const anonClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: authError } = await anonClient.auth.getUser();
    if (authError || !user) return json({ error: "Unauthorized" }, 401);

    const adminClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    // Monthly quota (atomic check-and-increment).
    const month = new Date().toISOString().slice(0, 7);
    const { data: quota, error: quotaError } = await adminClient.rpc("check_and_increment_usage", {
      p_user_id: user.id,
      p_feature: "suggest-condition",
      p_month: month,
    });
    if (quotaError) {
      console.error("rate limit rpc error:", quotaError);
      return json({ error: "Internal error" }, 500);
    }
    if (!quota.allowed) {
      return json({ error: "rate_limit_exceeded", remaining: 0, limit: quota.limit }, 429);
    }

    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!anthropicKey) return json({ error: "AI not configured" }, 500);

    const prompt = `Пользователь создаёт задачу в трекере привычек, где выполнение подтверждается фотографией.

Задача: "${title}"${description ? `\nОписание: "${description}"` : ""}

Сформулируй одно короткое условие на русском языке: что именно должно быть видно на фото, чтобы доказать выполнение этой задачи. Начни со слов "На фото". Пиши конкретно и естественно, без тире (используй обычные запятые).

Ответь ТОЛЬКО валидным JSON (без markdown):
{"condition":"На фото ..."}`;

    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": anthropicKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 200,
        messages: [{ role: "user", content: prompt }],
      }),
    });

    if (!res.ok) {
      console.error("Anthropic error:", await res.text());
      return json({ error: "AI temporarily unavailable" }, 502);
    }

    const data = await res.json();
    const text: string = data.content?.[0]?.text ?? "";
    let condition = "";
    try {
      const parsed = JSON.parse(text.replace(/```json\s*/gi, "").replace(/```/g, "").trim());
      condition = String(parsed.condition ?? "").trim();
    } catch {
      const m = text.match(/"condition"\s*:\s*"([^"]+)"/);
      condition = m?.[1]?.trim() ?? "";
    }
    // Strip any em-dashes the model slips in.
    condition = condition.replace(/\s*[—–]\s*/g, " -- ");

    if (!condition) return json({ error: "No suggestion" }, 502);
    return json({ condition, remaining: quota.remaining });
  } catch (error) {
    console.error("suggest-condition error:", error);
    return json({ error: "An error occurred" }, 500);
  }
});
