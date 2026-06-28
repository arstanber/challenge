import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { type Lang, pickLang, writeExplanationIn } from "../_shared/i18n.ts";

const MODEL = "claude-sonnet-4-5";

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

function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = "";
  for (let i = 0; i < bytes.byteLength; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary);
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let lang: Lang = "en";
  try {
    const body = await req.json();
    const { condition, photo_url, report_id, is_excuse = false, language } = body;
    lang = pickLang(language);
    const langNote = writeExplanationIn(lang);
    // Localized fallback explanations for paths that don't run the model.
    const EXPL = {
      notConfigured: { en: "AI verification not configured.", ru: "AI-проверка не настроена.", de: "KI-Verifizierung nicht konfiguriert.", kk: "AI тексеру бапталмаған." },
      noPhoto: { en: "Could not retrieve the photo.", ru: "Не удалось загрузить фото.", de: "Foto konnte nicht abgerufen werden.", kk: "Фотоны жүктеу мүмкін болмады." },
      unavailable: { en: "AI verification temporarily unavailable.", ru: "AI-проверка временно недоступна.", de: "KI-Verifizierung vorübergehend nicht verfügbar.", kk: "AI тексеру уақытша қолжетімсіз." },
      completed: { en: "Verification completed.", ru: "Проверка завершена.", de: "Verifizierung abgeschlossen.", kk: "Тексеру аяқталды." },
      error: { en: "An error occurred during verification.", ru: "Произошла ошибка во время проверки.", de: "Bei der Verifizierung ist ein Fehler aufgetreten.", kk: "Тексеру кезінде қате орын алды." },
    } as const;

    if (!condition || !photo_url) {
      return json({ error: "Missing condition or photo_url" }, 400);
    }

    const supabaseUrl = Deno.env.get("SUPABASE_URL")!;

    // Only verify photos that live in our own reports bucket
    if (!String(photo_url).startsWith(`${supabaseUrl}/storage/v1/object/public/reports/`)) {
      return json({ error: "photo_url must point to the reports bucket" }, 400);
    }

    // 1. Authenticate the caller -- user id comes from the verified JWT, never the body
    const authHeader = req.headers.get("Authorization") ?? "";
    const anonClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_ANON_KEY")!, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: authError } = await anonClient.auth.getUser();
    if (authError || !user) {
      return json({ error: "Unauthorized" }, 401);
    }

    const adminClient = createClient(supabaseUrl, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

    // 2. The report being verified must belong to the caller
    if (report_id) {
      const { data: report } = await adminClient
        .from("reports")
        .select("id, activities!inner(user_id)")
        .eq("id", report_id)
        .maybeSingle();
      const ownerId = (report as { activities?: { user_id?: string } } | null)?.activities?.user_id;
      if (!report || ownerId !== user.id) {
        return json({ error: "Report not found" }, 403);
      }
    }

    // 3. Enforce the monthly quota server-side (atomic check-and-increment)
    const month = new Date().toISOString().slice(0, 7); // "YYYY-MM"
    const { data: quota, error: quotaError } = await adminClient.rpc("check_and_increment_usage", {
      p_user_id: user.id,
      p_feature: "verify-report",
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
    if (!anthropicKey) {
      const explanation = EXPL.notConfigured[lang];
      return json({ approved: false, excused: false, explanation });
    }

    // 4. Fetch photo
    const photoResponse = await fetch(photo_url);
    if (!photoResponse.ok) {
      const explanation = EXPL.noPhoto[lang];
      return json({ approved: false, excused: false, explanation });
    }
    const photoBuffer = await photoResponse.arrayBuffer();
    const photoBase64 = arrayBufferToBase64(photoBuffer);
    const contentType = photoResponse.headers.get("content-type") || "image/jpeg";
    const mediaType = contentType.startsWith("image/") ? contentType.split(";")[0].trim() : "image/jpeg";

    // 5. Build prompt based on mode
    let prompt: string;

    if (is_excuse) {
      prompt = `You are evaluating a user's excuse for not completing an activity.

Activity they were supposed to do: "${condition}"

The user is submitting this photo as proof of why they could not complete the activity. Examine the photo carefully.

A VALID excuse is one of:
- Visible injury or physical harm (bandage, cast, visible wound, crutches, hospital setting)
- Clearly dangerous weather making the activity impossible or unsafe (flooding, blizzard, extreme storm)
- Medical emergency or illness (hospital bed, IV, ambulance)
- Equipment failure or facility closure shown in photo

An INVALID excuse is:
- Mild rain or normal bad weather
- Tiredness, laziness, or vague reasons
- Unrelated photos
- Photos that don't clearly show a reason

${langNote}

Respond ONLY with valid JSON (no markdown):
{"approved": false, "excused": boolean, "explanation": "1-2 sentence verdict"}`;
    } else {
      prompt = `You are verifying whether a submitted photo satisfies an activity condition.

Activity condition: "${condition}"

Examine the photo carefully. Does it genuinely show the user completing or working toward this activity?

- Be strict: the photo must clearly show the activity, not just imply it
- Look for: relevant equipment, location, body position, completion evidence
- Reject: unrelated photos, stock images, photos that don't show the activity

${langNote}

Respond ONLY with valid JSON (no markdown):
{"approved": boolean, "excused": false, "explanation": "1-2 sentence verdict"}`;
    }

    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": anthropicKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 256,
        messages: [{
          role: "user",
          content: [
            { type: "image", source: { type: "base64", media_type: mediaType, data: photoBase64 } },
            { type: "text", text: prompt },
          ],
        }],
      }),
    });

    if (!res.ok) {
      const err = await res.text();
      console.error("Anthropic error:", err);
      const explanation = EXPL.unavailable[lang];
      return json({ approved: false, excused: false, explanation });
    }

    const data = await res.json();
    const responseText: string = data.content?.[0]?.text ?? "";
    console.log("Claude response:", responseText.slice(0, 200));

    let result: { approved: boolean; excused: boolean; explanation: string };
    try {
      result = JSON.parse(responseText.replace(/```json\s*/gi, "").replace(/```/g, "").trim());
      if (typeof result.approved !== "boolean") throw new Error("bad shape");
      result.excused = result.excused ?? false;
    } catch {
      const approvedMatch = responseText.match(/"approved"\s*:\s*(true|false)/);
      const excusedMatch  = responseText.match(/"excused"\s*:\s*(true|false)/);
      result = {
        approved: approvedMatch?.[1] === "true",
        excused:  excusedMatch?.[1]  === "true",
        explanation: EXPL.completed[lang],
      };
    }

    // 6. Write the verdict server-side. Clients cannot write ai_result/ai_explanation
    //    (blocked by the protect_ai_verdict trigger) -- this is the only write path.
    if (report_id) {
      const aiResult = result.approved ? "approved" : result.excused ? "excused" : "rejected";
      const { error: writeError } = await adminClient
        .from("reports")
        .update({ ai_result: aiResult, ai_explanation: result.explanation })
        .eq("id", report_id);
      if (writeError) console.error("verdict write error:", writeError);
    }

    return json({ ...result, remaining: quota.remaining });
  } catch (error) {
    console.error("verify-report error:", error);
    const explanation = ({
      en: "An error occurred during verification.",
      ru: "Произошла ошибка во время проверки.",
      de: "Bei der Verifizierung ist ein Fehler aufgetreten.",
      kk: "Тексеру кезінде қате орын алды.",
    })[lang];
    return json({ approved: false, excused: false, explanation });
  }
});
