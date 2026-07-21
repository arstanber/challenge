// RevenueCat webhook -- the single source of truth for users.plan.
//
// RevenueCat POSTs one event per subscription lifecycle change (purchase,
// renewal, expiration, refund, transfer...). Rather than reasoning about each
// event type, we treat the event only as a trigger and then read the
// subscriber's CURRENT entitlements from the RevenueCat REST API. That is
// authoritative, idempotent, and immune to out-of-order delivery -- a retried
// or late event can never resurrect a stale plan.
//
// Security: RevenueCat sends a fixed Authorization header configured in the
// dashboard. We compare it against REVENUECAT_WEBHOOK_SECRET in constant time.
// The function must be deployed with --no-verify-jwt (RevenueCat cannot mint
// Supabase JWTs).
//
// Required secrets:
//   REVENUECAT_WEBHOOK_SECRET  -- shared string, also set in the RC dashboard
//   REVENUECAT_SECRET_API_KEY  -- RC secret key (sk_...), NOT the public appl_ key

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const RC_API = "https://api.revenuecat.com/v1/subscribers";

// Entitlement identifier -> plan tier. Must match Constants.RevenueCat in the app.
const ENTITLEMENT_PLANS: Record<string, string> = {
  premium: "premium",
  family: "family",
  max: "max",
};

const PLAN_RANK: Record<string, number> = { free: 0, premium: 1, family: 2, max: 3 };

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

/// Length-independent constant-time compare.
function safeEqual(a: string, b: string): boolean {
  const enc = new TextEncoder();
  const ab = enc.encode(a);
  const bb = enc.encode(b);
  let diff = ab.length ^ bb.length;
  const n = Math.max(ab.length, bb.length);
  for (let i = 0; i < n; i++) diff |= (ab[i] ?? 0) ^ (bb[i] ?? 0);
  return diff === 0;
}

/// Highest tier among the subscriber's currently-active entitlements.
function planFromEntitlements(entitlements: Record<string, any>): string {
  const now = Date.now();
  let best = "free";
  for (const [id, ent] of Object.entries(entitlements ?? {})) {
    // Case-insensitive: the identifiers are typed by hand in the RevenueCat
    // dashboard, and a case-only mismatch would silently leave paying users
    // on the free tier. Must stay in sync with Constants.RevenueCat.plan().
    const plan = ENTITLEMENT_PLANS[id.toLowerCase()];
    if (!plan) continue;
    // A null expires_date means a non-expiring (lifetime) entitlement.
    const expires = ent?.expires_date ? Date.parse(ent.expires_date) : Infinity;
    if (expires <= now) continue;
    if (PLAN_RANK[plan] > PLAN_RANK[best]) best = plan;
  }
  return best;
}

/// Reads the subscriber's live entitlement state from RevenueCat.
async function fetchPlan(appUserId: string, apiKey: string): Promise<string | null> {
  const res = await fetch(`${RC_API}/${encodeURIComponent(appUserId)}`, {
    headers: { Authorization: `Bearer ${apiKey}` },
  });
  if (!res.ok) {
    console.error(`RC subscriber fetch failed: ${res.status} ${await res.text()}`);
    return null;
  }
  const body = await res.json();
  return planFromEntitlements(body?.subscriber?.entitlements ?? {});
}

serve(async (req) => {
  if (req.method !== "POST") return json({ error: "method_not_allowed" }, 405);

  const expected = Deno.env.get("REVENUECAT_WEBHOOK_SECRET");
  const apiKey = Deno.env.get("REVENUECAT_SECRET_API_KEY");
  if (!expected || !apiKey) {
    console.error("Missing REVENUECAT_WEBHOOK_SECRET or REVENUECAT_SECRET_API_KEY");
    return json({ error: "misconfigured" }, 500);
  }
  if (!safeEqual(req.headers.get("Authorization") ?? "", expected)) {
    return json({ error: "unauthorized" }, 401);
  }

  try {
    const body = await req.json().catch(() => ({}));
    const event = body?.event ?? {};
    const type: string = event.type ?? "UNKNOWN";

    // Sandbox purchases must not grant real plans in production.
    if (event.environment === "SANDBOX" && Deno.env.get("RC_ALLOW_SANDBOX") !== "true") {
      return json({ ok: true, skipped: "sandbox" });
    }

    // TEST events from the dashboard's "Send test webhook" button carry a
    // dummy app_user_id and no real subscriber.
    if (type === "TEST") return json({ ok: true, skipped: "test_event" });

    // app_user_id is the Supabase user UUID (set via Purchases.logIn).
    // Anonymous IDs ($RCAnonymousID:...) belong to users who never signed in.
    const appUserId: string = event.app_user_id ?? "";
    const isUuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
      .test(appUserId);
    if (!isUuid) return json({ ok: true, skipped: "anonymous_user" });

    const plan = await fetchPlan(appUserId, apiKey);
    if (plan === null) return json({ error: "rc_fetch_failed" }, 502);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: user, error: userErr } = await admin
      .from("users")
      .select("id, plan, family_id")
      .eq("id", appUserId)
      .maybeSingle();
    if (userErr) throw userErr;
    if (!user) return json({ ok: true, skipped: "unknown_user" });

    // A child's plan is granted by the family buyer, not by any purchase of
    // their own. Downgrading them here would revoke family access over an
    // event that says nothing about the parent's subscription -- and would
    // surface as "the kid randomly lost access", impossible to trace back.
    // The parent's own events still cascade correctly further down.
    let isFamilyChild = false;
    if (plan === "free") {
      const { data: membership } = await admin
        .from("family_members")
        .select("child_user_id")
        .eq("child_user_id", appUserId)
        .maybeSingle();
      isFamilyChild = !!membership;
    }

    if (user.plan !== plan && !isFamilyChild) {
      const { error: updErr } = await admin
        .from("users")
        .update({ plan })
        .eq("id", appUserId);
      if (updErr) throw updErr;
      console.log(`plan ${user.plan} -> ${plan} for ${appUserId} (${type})`);
    } else if (isFamilyChild) {
      console.log(`skipped downgrade of family child ${appUserId} (${type})`);
    }

    // Family plans cascade to the buyer's children. Downgrades cascade too:
    // when the parent's family plan lapses, the children lose it with them.
    if (user.family_id) {
      const { data: fam } = await admin
        .from("families")
        .select("id")
        .eq("id", user.family_id)
        .eq("parent_user_id", appUserId)
        .maybeSingle();
      if (fam) {
        const memberPlan = plan === "family" || plan === "max" ? "premium" : "free";
        const { data: members } = await admin
          .from("family_members")
          .select("child_user_id")
          .eq("family_id", user.family_id);
        for (const m of members ?? []) {
          await admin
            .from("users")
            .update({ plan: memberPlan })
            .eq("id", m.child_user_id);
        }
      }
    }

    return json({ ok: true, plan });
  } catch (e) {
    console.error("revenuecat-webhook error:", e);
    return json({ error: String(e) }, 500);
  }
});
