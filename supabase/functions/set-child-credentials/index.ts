// Set or change a child account's real email + password.
//
// Two callers:
//   * the CHILD themselves (no child_id in body) -- forced on first sign-in to
//     replace the synthetic kid email / PIN password with real credentials;
//   * the PARENT of the child (child_id in body) -- to change them later.
//
// Uses the admin API so the email change applies immediately (email_confirm),
// then mirrors the new email onto public.users and marks child_credentials_set.
//
// Security: the caller is identified from the VERIFIED JWT, never the body.

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
    const { data: { user: caller }, error: authErr } = await anon.auth.getUser();
    if (authErr || !caller) return json({ error: "Unauthorized" }, 401);

    const body = await req.json().catch(() => ({}));
    const childId = typeof body.child_id === "string" ? body.child_id : null;
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    const password = typeof body.password === "string" ? body.password : "";

    if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return json({ error: "invalid_email" }, 400);
    if (password.length < 6) return json({ error: "password_too_short" }, 400);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // Resolve the target child and authorize the caller.
    let targetId: string;
    if (childId) {
      // Parent path: caller must own the family the child belongs to.
      const { data: child } = await admin
        .from("users")
        .select("id, family_id, is_child_account")
        .eq("id", childId)
        .maybeSingle();
      if (!child?.is_child_account) return json({ error: "not_a_child" }, 400);
      const { data: fam } = await admin
        .from("families")
        .select("id")
        .eq("id", child.family_id)
        .eq("parent_user_id", caller.id)
        .maybeSingle();
      if (!fam) return json({ error: "not_your_child" }, 403);
      targetId = childId;
    } else {
      // Child path: caller sets their own credentials.
      const { data: me } = await admin
        .from("users")
        .select("is_child_account")
        .eq("id", caller.id)
        .maybeSingle();
      if (!me?.is_child_account) return json({ error: "not_a_child" }, 400);
      targetId = caller.id;
    }

    // Reject an email already used by a different account.
    const { data: clash } = await admin
      .from("users")
      .select("id")
      .eq("email", email)
      .neq("id", targetId)
      .maybeSingle();
    if (clash) return json({ error: "email_in_use" }, 409);

    const { error: updErr } = await admin.auth.admin.updateUserById(targetId, {
      email,
      password,
      email_confirm: true,
    });
    if (updErr) return json({ error: updErr.message }, 500);

    const { error: rowErr } = await admin
      .from("users")
      .update({ email, child_credentials_set: true })
      .eq("id", targetId);
    if (rowErr) return json({ error: rowErr.message }, 500);

    return json({ ok: true });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
