import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const APNS_HOST = "https://api.push.apple.com";

// MARK: - APNs ES256 JWT

function base64url(data: Uint8Array): string {
  return btoa(String.fromCharCode(...data))
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=/g, "");
}

async function makeApnsJwt(
  keyId: string,
  teamId: string,
  pem: string
): Promise<string> {
  const pemBody = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s/g, "");

  const keyBytes = Uint8Array.from(atob(pemBody), (c) => c.charCodeAt(0));

  const privateKey = await crypto.subtle.importKey(
    "pkcs8",
    keyBytes,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );

  const enc = new TextEncoder();
  const header = base64url(enc.encode(JSON.stringify({ alg: "ES256", kid: keyId })));
  const payload = base64url(
    enc.encode(JSON.stringify({ iss: teamId, iat: Math.floor(Date.now() / 1000) }))
  );
  const unsigned = `${header}.${payload}`;

  const sig = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    privateKey,
    enc.encode(unsigned)
  );

  return `${unsigned}.${base64url(new Uint8Array(sig))}`;
}

// MARK: - Handler

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
    // Require a genuine authenticated user. Default JWT verification also
    // accepts the bare anon key, which would let anyone trigger pushes to an
    // arbitrary user_id -- so verify there is a real user behind the token.
    // Exception: trusted server-to-server callers (cron jobs, other edge
    // functions) may present the service-role key instead of a user token.
    const authHeader = req.headers.get("Authorization") ?? "";
    const bearer = authHeader.replace(/^Bearer\s+/i, "");
    const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
    if (bearer !== serviceKey) {
      const authClient = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_ANON_KEY")!,
        { global: { headers: { Authorization: authHeader } } }
      );
      const { data: { user: caller }, error: authErr } = await authClient.auth.getUser();
      if (authErr || !caller) {
        return json({ error: "Unauthorized" }, 401);
      }
    }

    const keyId      = Deno.env.get("APNS_KEY_ID");
    const teamId     = Deno.env.get("APNS_TEAM_ID");
    const bundleId   = Deno.env.get("APNS_BUNDLE_ID");
    const privateKey = Deno.env.get("APNS_PRIVATE_KEY");

    if (!keyId || !teamId || !bundleId || !privateKey) {
      return json({ error: "APNs secrets not configured" }, 500);
    }

    // content_state (optional): when present AND the user has a running Live
    // Activity, the same notification is also routed through the Dynamic Island.
    const { user_id, title, body, data, content_state } = await req.json();
    if (!user_id || !title) {
      return json({ error: "user_id and title are required" }, 400);
    }

    // Fetch device token from push_tokens table
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    const { data: row, error: rowErr } = await supabase
      .from("push_tokens")
      .select("apns_token, live_activity_token")
      .eq("user_id", user_id)
      .single();

    if (rowErr || (!row?.apns_token && !row?.live_activity_token)) {
      return json({ error: "No push token found for this user" }, 404);
    }

    const jwt = await makeApnsJwt(keyId, teamId, privateKey);

    // Prefer routing through the Live Activity when one is running and a fresh
    // content state was supplied: a single liveactivity push both updates the
    // island AND shows the banner + sound, so we skip the duplicate alert push.
    if (content_state && row?.live_activity_token) {
      const now = Math.floor(Date.now() / 1000);
      const laRes = await fetch(`${APNS_HOST}/3/device/${row.live_activity_token}`, {
        method: "POST",
        headers: {
          authorization: `bearer ${jwt}`,
          "apns-topic": `${bundleId}.push-type.liveactivity`,
          "apns-push-type": "liveactivity",
          "apns-priority": "10",
          "content-type": "application/json",
        },
        body: JSON.stringify({
          aps: {
            timestamp: now,
            event: "update",
            "content-state": content_state,
            "stale-date": now + 3600,
            "relevance-score": 100,
            alert: { title, body: body ?? "" },
          },
        }),
      });
      if (laRes.ok) return json({ ok: true, via: "live-activity" });
      if (laRes.status === 410) {
        await supabase.from("push_tokens")
          .update({ live_activity_token: null }).eq("user_id", user_id);
      }
      // Fall through to the regular alert push on any failure.
    }

    if (!row?.apns_token) {
      return json({ error: "No alert push token for this user" }, 404);
    }

    const apnsPayload = {
      aps: {
        alert: { title, body: body ?? "" },
        // Branded chime bundled in the app; old clients without the file fall
        // back to the system default automatically.
        sound: "chime.caf",
        badge: 1,
      },
      ...(data ?? {}),
    };

    const apnsRes = await fetch(`${APNS_HOST}/3/device/${row.apns_token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": bundleId,
        "apns-push-type": "alert",
        "apns-priority": "10",
        "content-type": "application/json",
      },
      body: JSON.stringify(apnsPayload),
    });

    if (!apnsRes.ok) {
      const errText = await apnsRes.text();
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
