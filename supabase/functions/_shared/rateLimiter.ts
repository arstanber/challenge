import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

export type Feature =
  | "verify-report"
  | "parse-tasks-group"
  | "coach-group"
  | "ai-chat"
  | "plan-goal";

export interface RateLimitOk {
  allowed: true;
  userId: string;
  remaining: number;
}

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

/**
 * Verifies the JWT from the request, then atomically checks + increments usage.
 * Returns either a ready-to-send Response (error) or RateLimitOk (proceed).
 *
 * Security properties:
 *  - user_id is extracted from the VERIFIED JWT, never from the request body
 *  - the check+increment is a single Postgres transaction (no race conditions)
 *  - the SQL function is SECURITY DEFINER and revoked from anon/authenticated,
 *    so it can only be called with the service_role key — never directly by clients
 */
export async function checkRateLimit(
  req: Request,
  feature: Feature
): Promise<RateLimitOk | Response> {
  // 1. Extract JWT from Authorization header
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  // 2. Verify JWT via Supabase auth — this is cryptographically verified,
  //    an attacker cannot forge a token for a different user_id
  const anonClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } }
  );
  const { data: { user }, error: authError } = await anonClient.auth.getUser();
  if (authError || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  // 3. Call the atomic Postgres function using service_role key.
  //    The function is REVOKED from anon/authenticated — only reachable here.
  const adminClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
  );
  const month = new Date().toISOString().slice(0, 7); // "YYYY-MM"
  const { data, error: rpcError } = await adminClient.rpc("check_and_increment_usage", {
    p_user_id: user.id,
    p_feature: feature,
    p_month:   month,
  });

  if (rpcError) {
    console.error("rate_limit rpc error:", rpcError);
    return new Response(JSON.stringify({ error: "Internal error" }), {
      status: 500,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  if (!data.allowed) {
    return new Response(
      JSON.stringify({ error: "rate_limit_exceeded", remaining: 0, limit: data.limit }),
      {
        status: 429,
        headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
      }
    );
  }

  return { allowed: true, userId: user.id, remaining: data.remaining };
}

/**
 * Verifies the JWT only — does NOT touch the usage counter.
 * Use this in helper functions that are part of a larger flow already charged elsewhere.
 * Returns the userId string on success, or a ready-to-send error Response.
 */
export async function verifyAuth(req: Request): Promise<string | Response> {
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }

  const anonClient = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: authHeader } } }
  );
  const { data: { user }, error } = await anonClient.auth.getUser();
  if (error || !user) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
    });
  }
  return user.id;
}

export { CORS_HEADERS };
