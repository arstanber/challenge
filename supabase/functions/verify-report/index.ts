import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const MODEL = "claude-sonnet-4-5";

function arrayBufferToBase64(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let binary = "";
  for (let i = 0; i < bytes.byteLength; i++) binary += String.fromCharCode(bytes[i]);
  return btoa(binary);
}

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), { status: 405, headers: { "Content-Type": "application/json" } });
  }

  try {
    const body = await req.json();
    const { condition, photo_url, is_excuse = false } = body;

    if (!condition || !photo_url) {
      return new Response(JSON.stringify({ error: "Missing condition or photo_url" }), { status: 400, headers: { "Content-Type": "application/json" } });
    }

    const anthropicKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!anthropicKey) {
      return new Response(
        JSON.stringify({ approved: false, excused: false, explanation: "AI verification not configured." }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }

    // Fetch photo
    const photoResponse = await fetch(photo_url);
    if (!photoResponse.ok) {
      return new Response(
        JSON.stringify({ approved: false, excused: false, explanation: "Could not retrieve the photo." }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
    }
    const photoBuffer = await photoResponse.arrayBuffer();
    const photoBase64 = arrayBufferToBase64(photoBuffer);
    const contentType = photoResponse.headers.get("content-type") || "image/jpeg";
    const mediaType = contentType.startsWith("image/") ? contentType.split(";")[0].trim() : "image/jpeg";

    // Build prompt based on mode
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

Respond ONLY with valid JSON (no markdown):
{"approved": false, "excused": boolean, "explanation": "1-2 sentence verdict"}`;
    } else {
      prompt = `You are verifying whether a submitted photo satisfies an activity condition.

Activity condition: "${condition}"

Examine the photo carefully. Does it genuinely show the user completing or working toward this activity?

- Be strict: the photo must clearly show the activity, not just imply it
- Look for: relevant equipment, location, body position, completion evidence
- Reject: unrelated photos, stock images, photos that don't show the activity

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
      return new Response(
        JSON.stringify({ approved: false, excused: false, explanation: "AI verification temporarily unavailable." }),
        { status: 200, headers: { "Content-Type": "application/json" } }
      );
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
        approved: approvedMatch?.[1] === "true" ?? false,
        excused:  excusedMatch?.[1]  === "true" ?? false,
        explanation: "Verification completed.",
      };
    }

    return new Response(JSON.stringify(result), {
      headers: { "Content-Type": "application/json", "Connection": "keep-alive" },
    });
  } catch (error) {
    console.error("verify-report error:", error);
    return new Response(
      JSON.stringify({ approved: false, excused: false, explanation: "An error occurred during verification." }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  }
});
