import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { CORS_HEADERS, verifyAuth } from "../_shared/rateLimiter.ts";
import { type Lang, pickLang, respondIn } from "../_shared/i18n.ts";

const PERPLEXITY_URL = "https://api.perplexity.ai/chat/completions";
const MODEL = "sonar";

type Step = { title: string; details: string };
type Resource = { title: string; url: string; description: string };
type Guide = {
  title: string;
  overview: string;
  steps: Step[];
  safetyNotes: string[];
  resources: Resource[];
};

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

function cleanText(value: unknown, maxLength: number): string {
  return typeof value === "string"
    ? value.trim().replace(/[—–]/g, "--").slice(0, maxLength)
    : "";
}

function isYouTubeURL(value: string): boolean {
  try {
    const host = new URL(value).hostname.toLowerCase().replace(/^www\./, "");
    return host === "youtube.com" || host.endsWith(".youtube.com") || host === "youtu.be";
  } catch {
    return false;
  }
}

function normalizeGuide(value: unknown): Guide | null {
  if (!value || typeof value !== "object") return null;
  const raw = value as Record<string, unknown>;

  const steps = (Array.isArray(raw.steps) ? raw.steps : [])
    .filter((item): item is Record<string, unknown> => !!item && typeof item === "object")
    .map((item) => ({
      title: cleanText(item.title, 100),
      details: cleanText(item.details, 500),
    }))
    .filter((item) => item.title && item.details)
    .slice(0, 7);

  const safetyNotes = (Array.isArray(raw.safetyNotes) ? raw.safetyNotes : [])
    .map((item) => cleanText(item, 300))
    .filter(Boolean)
    .slice(0, 4);

  const resources = (Array.isArray(raw.resources) ? raw.resources : [])
    .filter((item): item is Record<string, unknown> => !!item && typeof item === "object")
    .map((item) => ({
      title: cleanText(item.title, 160),
      url: cleanText(item.url, 800),
      description: cleanText(item.description, 240),
    }))
    .filter((item) => item.title && isYouTubeURL(item.url))
    .slice(0, 5);

  const title = cleanText(raw.title, 140);
  const overview = cleanText(raw.overview, 800);
  if (!title || !overview || steps.length === 0) return null;

  return { title, overview, steps, safetyNotes, resources };
}

async function fingerprint(parts: string[]): Promise<string> {
  const bytes = new TextEncoder().encode(parts.join("\u001f"));
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const authResult = await verifyAuth(req);
  if (authResult instanceof Response) return authResult;
  const userId = authResult;

  try {
    const body = await req.json();
    const activityId = cleanText(body.activityId, 80);
    const language: Lang = pickLang(body.language);
    const forceRefresh = body.forceRefresh === true;
    if (!activityId) return json({ error: "missing_activity_id" }, 400);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const [{ data: profile, error: profileError }, { data: activity, error: activityError }] =
      await Promise.all([
        admin.from("users").select("plan").eq("id", userId).single(),
        admin
          .from("activities")
          .select("id, user_id, title, description, condition, type")
          .eq("id", activityId)
          .eq("user_id", userId)
          .single(),
      ]);

    if (profileError || !profile) return json({ error: "profile_not_found" }, 404);
    if (profile.plan !== "max") return json({ error: "max_required" }, 403);
    if (activityError || !activity) return json({ error: "activity_not_found" }, 404);

    const sourceFingerprint = await fingerprint([
      activity.title ?? "",
      activity.description ?? "",
      activity.condition ?? "",
      activity.type ?? "",
    ]);

    const { data: cached } = await admin
      .from("activity_learning_guides")
      .select("guide, generated_at, source_fingerprint")
      .eq("activity_id", activityId)
      .eq("language", language)
      .maybeSingle();

    const cachedGuide = normalizeGuide(cached?.guide);
    const cachedAgeMs = cached?.generated_at
      ? Date.now() - new Date(cached.generated_at).getTime()
      : Number.POSITIVE_INFINITY;
    const sourceMatches = cached?.source_fingerprint === sourceFingerprint;

    // Normal openings are free. A manual refresh can generate at most once
    // every 15 minutes for a task, which prevents accidental repeated charges.
    if (cachedGuide && sourceMatches && (!forceRefresh || cachedAgeMs < 15 * 60 * 1000)) {
      return json({ ...cachedGuide, generatedAt: cached.generated_at, cached: true });
    }

    // Defense in depth for Max accounts with many tasks: cap the number of
    // different guides freshly generated for one user during an hour.
    const oneHourAgo = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const { count: recentGenerationCount, error: countError } = await admin
      .from("activity_learning_guides")
      .select("id", { count: "exact", head: true })
      .eq("user_id", userId)
      .gte("generated_at", oneHourAgo);
    if (countError) console.error("learning guide rate-limit query error:", countError);
    if ((recentGenerationCount ?? 0) >= 20) {
      return json({ error: "learning_rate_limit_exceeded" }, 429);
    }

    const perplexityKey = Deno.env.get("PERPLEXITY_API_KEY");
    if (!perplexityKey) return json({ error: "learning_ai_not_configured" }, 503);

    const context = [
      `Task: ${activity.title}`,
      activity.description ? `Description: ${activity.description}` : "",
      activity.condition ? `Completion condition: ${activity.condition}` : "",
      `Task type: ${activity.type}`,
    ].filter(Boolean).join("\n");

    const prompt = `Create a practical beginner-friendly learning guide for this task in the reInspire habit app.

${context}

${respondIn(language)}
Use only information supported by the web search results. If the topic involves health, medicine, physical risk, finance, or law, include a concise safety note and advise professional help when appropriate. Never invent a video URL. Choose 3 to 5 directly relevant YouTube videos from the search results.

Return ONLY valid JSON without markdown:
{
  "title": "short guide title",
  "overview": "2 to 4 concise sentences",
  "steps": [
    {"title": "step title", "details": "clear actionable explanation"}
  ],
  "safetyNotes": ["important warning when relevant"],
  "resources": [
    {"title": "exact video title", "url": "YouTube URL from search results", "description": "why it helps"}
  ]
}`;

    const perplexityResponse = await fetch(PERPLEXITY_URL, {
      method: "POST",
      headers: {
        "Authorization": `Bearer ${perplexityKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: MODEL,
        messages: [
          {
            role: "system",
            content: "Use search results only. Say when reliable material is insufficient. Return strict JSON.",
          },
          { role: "user", content: prompt },
        ],
        search_domain_filter: ["youtube.com", "youtu.be"],
        search_context_size: "low",
        temperature: 0.2,
        max_tokens: 1400,
        response_format: { type: "json_object" },
      }),
    });

    if (!perplexityResponse.ok) {
      console.error("Perplexity error:", perplexityResponse.status, await perplexityResponse.text());
      return json({ error: "learning_ai_unavailable" }, 502);
    }

    const perplexityData = await perplexityResponse.json();
    const rawText = perplexityData.choices?.[0]?.message?.content ?? "";
    let parsed: unknown;
    try {
      parsed = JSON.parse(String(rawText).replace(/```json\s*/gi, "").replace(/```/g, "").trim());
    } catch {
      return json({ error: "invalid_learning_guide" }, 502);
    }

    const guide = normalizeGuide(parsed);
    if (!guide) return json({ error: "invalid_learning_guide" }, 502);

    const generatedAt = new Date().toISOString();
    const { error: cacheError } = await admin
      .from("activity_learning_guides")
      .upsert({
        activity_id: activityId,
        user_id: userId,
        language,
        source_fingerprint: sourceFingerprint,
        guide,
        generated_at: generatedAt,
      }, { onConflict: "activity_id,language" });

    if (cacheError) console.error("learning guide cache error:", cacheError);
    return json({ ...guide, generatedAt, cached: false });
  } catch (error) {
    console.error("generate-learning-guide error:", error);
    return json({ error: "internal_error" }, 500);
  }
});
