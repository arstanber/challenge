// Edge Function: connector-oauth
// Handles OAuth2 token exchange / refresh / data fetch for third-party fitness connectors.
// Client secrets live ONLY here (as function secrets); the app never sees them.
//
// Actions (POST body): { action, provider, ... }
//   exchange   { code, redirectUri }  → swap auth code for tokens, store them
//   today      { metric }             → return today's value for that metric
//   disconnect {}                     → delete stored tokens
import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { verifyAuth, CORS_HEADERS } from "../_shared/rateLimiter.ts";

interface ProviderCfg {
  tokenURL: string;
  clientId: string;
  clientSecret: string;
  /** true = send credentials as HTTP Basic header (Fitbit, Whoop, Garmin); false = in body. */
  basicAuth: boolean;
}

function providerConfig(provider: string): ProviderCfg {
  const env = (k: string) => Deno.env.get(k) ?? "";
  switch (provider) {
    case "strava":
      return { tokenURL: "https://www.strava.com/oauth/token", clientId: env("STRAVA_CLIENT_ID"), clientSecret: env("STRAVA_CLIENT_SECRET"), basicAuth: false };
    case "googleFit":
      return { tokenURL: "https://oauth2.googleapis.com/token", clientId: env("GOOGLE_CLIENT_ID"), clientSecret: env("GOOGLE_CLIENT_SECRET"), basicAuth: false };
    case "fitbit":
      return { tokenURL: "https://api.fitbit.com/oauth2/token", clientId: env("FITBIT_CLIENT_ID"), clientSecret: env("FITBIT_CLIENT_SECRET"), basicAuth: true };
    case "whoop":
      return { tokenURL: "https://api.prod.whoop.com/oauth/oauth2/token", clientId: env("WHOOP_CLIENT_ID"), clientSecret: env("WHOOP_CLIENT_SECRET"), basicAuth: false };
    case "garmin":
      return { tokenURL: "https://diauth.garmin.com/di-oauth2-service/oauth/token", clientId: env("GARMIN_CLIENT_ID"), clientSecret: env("GARMIN_CLIENT_SECRET"), basicAuth: true };
    default:
      throw new Error(`unknown provider: ${provider}`);
  }
}

const admin = () =>
  createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

// deno-lint-ignore no-explicit-any
async function tokenRequest(provider: string, params: URLSearchParams): Promise<any> {
  const cfg = providerConfig(provider);
  const headers: Record<string, string> = { "Content-Type": "application/x-www-form-urlencoded" };
  if (cfg.basicAuth) {
    headers["Authorization"] = "Basic " + btoa(`${cfg.clientId}:${cfg.clientSecret}`);
  } else {
    params.set("client_id", cfg.clientId);
    params.set("client_secret", cfg.clientSecret);
  }
  const res = await fetch(cfg.tokenURL, { method: "POST", headers, body: params.toString() });
  const text = await res.text();
  if (!res.ok) throw new Error(`token endpoint ${res.status}: ${text}`);
  return JSON.parse(text);
}

function exchangeCode(provider: string, code: string, redirectUri: string) {
  return tokenRequest(provider, new URLSearchParams({
    grant_type: "authorization_code",
    code,
    redirect_uri: redirectUri,
  }));
}

function refresh(provider: string, refreshToken: string) {
  return tokenRequest(provider, new URLSearchParams({
    grant_type: "refresh_token",
    refresh_token: refreshToken,
  }));
}

// deno-lint-ignore no-explicit-any
async function saveToken(userId: string, provider: string, tok: any) {
  const expiresAt = tok.expires_in
    ? new Date(Date.now() + Number(tok.expires_in) * 1000).toISOString()
    : tok.expires_at
    ? new Date(Number(tok.expires_at) * 1000).toISOString()
    : null;
  await admin().from("connector_tokens").upsert({
    user_id: userId,
    provider,
    access_token: tok.access_token,
    refresh_token: tok.refresh_token ?? null,
    expires_at: expiresAt,
    scope: tok.scope ?? null,
    updated_at: new Date().toISOString(),
  });
}

async function getValidToken(userId: string, provider: string): Promise<string | null> {
  const { data } = await admin()
    .from("connector_tokens").select("*")
    .eq("user_id", userId).eq("provider", provider).maybeSingle();
  if (!data) return null;

  const nearlyExpired = data.expires_at &&
    new Date(data.expires_at).getTime() < Date.now() + 60_000;
  if (nearlyExpired && data.refresh_token) {
    const tok = await refresh(provider, data.refresh_token);
    // Some providers rotate refresh tokens; keep the old one if a new one isn't returned.
    await saveToken(userId, provider, { ...tok, refresh_token: tok.refresh_token ?? data.refresh_token });
    return tok.access_token;
  }
  return data.access_token;
}

// Returns today's value for the requested metric (steps / activeEnergy(kcal) / exerciseMinutes / distance(m)).
async function fetchToday(provider: string, metric: string, token: string): Promise<number> {
  const todayStr = new Date().toISOString().slice(0, 10);
  const startEpoch = Math.floor(new Date(`${todayStr}T00:00:00Z`).getTime() / 1000);
  const bearer = { Authorization: `Bearer ${token}` };

  switch (provider) {
    case "strava": {
      const res = await fetch(`https://www.strava.com/api/v3/athlete/activities?after=${startEpoch}&per_page=100`, { headers: bearer });
      const acts = await res.json();
      if (!Array.isArray(acts)) return 0;
      if (metric === "distance") return acts.reduce((s, a) => s + (a.distance ?? 0), 0);
      if (metric === "activeEnergy") return acts.reduce((s, a) => s + (a.calories ?? a.kilojoules ?? 0), 0);
      if (metric === "exerciseMinutes") return acts.reduce((s, a) => s + (a.moving_time ?? 0), 0) / 60;
      return acts.length; // steps not available from Strava
    }
    case "fitbit": {
      const res = await fetch(`https://api.fitbit.com/1/user/-/activities/date/${todayStr}.json`, { headers: bearer });
      const d = await res.json();
      const s = d.summary ?? {};
      if (metric === "steps") return s.steps ?? 0;
      if (metric === "activeEnergy") return s.activityCalories ?? s.caloriesOut ?? 0;
      if (metric === "distance") {
        // deno-lint-ignore no-explicit-any
        const t = (s.distances ?? []).find((x: any) => x.activity === "total");
        return (t?.distance ?? 0) * 1000;
      }
      if (metric === "exerciseMinutes") return (s.fairlyActiveMinutes ?? 0) + (s.veryActiveMinutes ?? 0);
      return s.steps ?? 0;
    }
    case "googleFit": {
      const dataType = metric === "steps" ? "com.google.step_count.delta"
        : metric === "activeEnergy" ? "com.google.calories.expended"
        : metric === "distance" ? "com.google.distance.delta"
        : "com.google.active_minutes";
      const res = await fetch("https://www.googleapis.com/fitness/v1/users/me/dataset:aggregate", {
        method: "POST",
        headers: { ...bearer, "Content-Type": "application/json" },
        body: JSON.stringify({
          aggregateBy: [{ dataTypeName: dataType }],
          bucketByTime: { durationMillis: 86_400_000 },
          startTimeMillis: startEpoch * 1000,
          endTimeMillis: Date.now(),
        }),
      });
      const d = await res.json();
      let total = 0;
      for (const b of d.bucket ?? [])
        for (const ds of b.dataset ?? [])
          for (const p of ds.point ?? [])
            for (const v of p.value ?? []) total += v.fpVal ?? v.intVal ?? 0;
      return total;
    }
    case "whoop": {
      // Whoop has no steps; expose calories (kJ→kcal) / workout minutes.
      const res = await fetch(`https://api.prod.whoop.com/developer/v1/activity/workout?start=${todayStr}T00:00:00.000Z`, { headers: bearer });
      const d = await res.json();
      const recs = d.records ?? [];
      // deno-lint-ignore no-explicit-any
      if (metric === "activeEnergy") return recs.reduce((s: number, r: any) => s + ((r.score?.kilojoule ?? 0) / 4.184), 0);
      // deno-lint-ignore no-explicit-any
      if (metric === "exerciseMinutes") return recs.reduce((s: number, r: any) => s + (new Date(r.end).getTime() - new Date(r.start).getTime()) / 60000, 0);
      return recs.length;
    }
    case "garmin":
      // Garmin Health API is partner-gated; implement once your program is approved.
      return 0;
    default:
      return 0;
  }
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  const auth = await verifyAuth(req);
  if (auth instanceof Response) return auth;
  const userId = auth;

  try {
    const body = await req.json();
    const { action, provider } = body;

    switch (action) {
      case "exchange": {
        const tok = await exchangeCode(provider, body.code, body.redirectUri);
        await saveToken(userId, provider, tok);
        return json({ ok: true });
      }
      case "disconnect": {
        await admin().from("connector_tokens").delete().eq("user_id", userId).eq("provider", provider);
        return json({ ok: true });
      }
      case "today": {
        const token = await getValidToken(userId, provider);
        if (!token) return json({ value: null, error: "not_connected" });
        const value = await fetchToday(provider, body.metric, token);
        return json({ value });
      }
      default:
        return json({ error: "unknown_action" }, 400);
    }
  } catch (e) {
    return json({ error: String(e) });
  }
});
