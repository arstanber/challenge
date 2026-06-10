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
    const keyId      = Deno.env.get("APNS_KEY_ID");
    const teamId     = Deno.env.get("APNS_TEAM_ID");
    const bundleId   = Deno.env.get("APNS_BUNDLE_ID");
    const privateKey = Deno.env.get("APNS_PRIVATE_KEY");

    if (!keyId || !teamId || !bundleId || !privateKey) {
      return json({ error: "APNs secrets not configured" }, 500);
    }

    const { user_id, title, body, data } = await req.json();
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
      .select("apns_token")
      .eq("user_id", user_id)
      .single();

    if (rowErr || !row?.apns_token) {
      return json({ error: "No push token found for this user" }, 404);
    }

    const jwt = await makeApnsJwt(keyId, teamId, privateKey);

    const apnsPayload = {
      aps: {
        alert: { title, body: body ?? "" },
        sound: "default",
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
