// Edge Function: push-live-activity (#20c)
// Sends an APNs Live Activity push so the Dynamic Island / Lock Screen banner
// updates remotely (even when the app is backgrounded). The caller provides the
// content_state object verbatim -- its keys must match the Swift
// ReInspireActivityAttributes.ContentState (todayDone, streakCurrent,
// nextTaskTitle, goalReached, tasks, flashApproved).
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const APNS_HOST = "https://api.push.apple.com";

function base64url(data: Uint8Array): string {
  return btoa(String.fromCharCode(...data))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");
}

async function makeApnsJwt(keyId: string, teamId: string, pem: string): Promise<string> {
  const pemBody = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");
  const keyBytes = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));
  const privateKey = await crypto.subtle.importKey(
    "pkcs8", keyBytes, { name: "ECDSA", namedCurve: "P-256" }, false, ["sign"]
  );
  const enc = new TextEncoder();
  const header = base64url(enc.encode(JSON.stringify({ alg: "ES256", kid: keyId })));
  const payload = base64url(enc.encode(JSON.stringify({ iss: teamId, iat: Math.floor(Date.now() / 1000) })));
  const unsigned = `${header}.${payload}`;
  const sig = await crypto.subtle.sign({ name: "ECDSA", hash: "SHA-256" }, privateKey, enc.encode(unsigned));
  return `${unsigned}.${base64url(new Uint8Array(sig))}`;
}

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
      },
    });
  }

  try {
    const keyId      = Deno.env.get("APNS_KEY_ID");
    const teamId     = Deno.env.get("APNS_TEAM_ID");
    const bundleId   = Deno.env.get("APNS_BUNDLE_ID");
    const privateKey = Deno.env.get("APNS_PRIVATE_KEY");
    if (!keyId || !teamId || !bundleId || !privateKey) {
      return json({ error: "APNs secrets not configured" }, 500);
    }

    // event: "update" (default) | "end". alert is optional -- when present the
    // push also surfaces as a notification banner + sound, mirroring a normal
    // push but routed through the activity.
    const { user_id, content_state, alert, event = "update", stale_minutes = 60, dismiss_minutes } =
      await req.json();

    if (!user_id) return json({ error: "user_id is required" }, 400);
    if (event === "update" && !content_state) {
      return json({ error: "content_state is required for update events" }, 400);
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const { data: row, error: rowErr } = await supabase
      .from("push_tokens")
      .select("live_activity_token")
      .eq("user_id", user_id)
      .single();

    if (rowErr || !row?.live_activity_token) {
      return json({ error: "No Live Activity token for this user" }, 404);
    }

    const jwt = await makeApnsJwt(keyId, teamId, privateKey);
    const now = Math.floor(Date.now() / 1000);

    const aps: Record<string, unknown> = { timestamp: now, event };
    if (content_state) aps["content-state"] = content_state;
    if (event === "update") {
      aps["stale-date"] = now + stale_minutes * 60;
      aps["relevance-score"] = 100;
    }
    if (event === "end" && dismiss_minutes != null) {
      aps["dismissal-date"] = now + dismiss_minutes * 60;
    }
    if (alert?.title) aps["alert"] = { title: alert.title, body: alert.body ?? "" };

    const apnsRes = await fetch(`${APNS_HOST}/3/device/${row.live_activity_token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        // Live Activity pushes use the dedicated push-type topic suffix.
        "apns-topic": `${bundleId}.push-type.liveactivity`,
        "apns-push-type": "liveactivity",
        "apns-priority": "10",
        "content-type": "application/json",
      },
      body: JSON.stringify({ aps }),
    });

    if (!apnsRes.ok) {
      const errText = await apnsRes.text();
      // A 410 means the activity ended; drop the stale token so we stop trying.
      if (apnsRes.status === 410) {
        await supabase.from("push_tokens")
          .update({ live_activity_token: null })
          .eq("user_id", user_id);
      }
      return json({ error: `APNs ${apnsRes.status}: ${errText}` }, 502);
    }

    return json({ ok: true });
  } catch (err) {
    return json({ error: String(err) }, 500);
  }
});

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
