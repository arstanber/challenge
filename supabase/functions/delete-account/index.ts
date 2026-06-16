// GDPR "right to erasure" -- permanently delete the calling user's account.
//
// The caller is identified ONLY from the verified JWT, never the body, so a
// user can erase their own account and nobody else's. We delete in this order:
//   1. best-effort: their avatar object in Storage
//   2. their public.users row (cascades to activities, reports, streak_freezes,
//      referrals, duels, connector_tokens, telegram_links, ... via ON DELETE
//      CASCADE foreign keys)
//   3. their auth.users identity (the login itself)
//
// Children of a family parent are intentionally left intact -- erasing a parent
// must not silently destroy a child's separate account.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });

  try {
    const authHeader = req.headers.get("Authorization") ?? "";
    if (!authHeader.startsWith("Bearer ")) return json({ error: "Unauthorized" }, 401);

    const anon = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authHeader } } },
    );
    const { data: { user }, error: authErr } = await anon.auth.getUser();
    if (authErr || !user) return json({ error: "Unauthorized" }, 401);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // 1. Avatar in Storage (best-effort -- the file may not exist).
    try {
      const { data: avatars } = await admin.storage.from("avatars").list(user.id);
      if (avatars?.length) {
        await admin.storage
          .from("avatars")
          .remove(avatars.map((f) => `${user.id}/${f.name}`));
      }
    } catch (_) { /* ignore -- erasure of the row below is what matters */ }

    // 2. The profile row -- cascades to all owned data.
    const { error: delErr } = await admin.from("users").delete().eq("id", user.id);
    if (delErr) return json({ error: delErr.message }, 500);

    // 3. The auth identity itself.
    const { error: authDelErr } = await admin.auth.admin.deleteUser(user.id);
    if (authDelErr) return json({ error: authDelErr.message }, 500);

    return json({ ok: true });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
