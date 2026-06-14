// Parent-provisioned child account.
//
// A family parent posts { name, pin }. We create a Supabase auth user with a
// synthetic, non-deliverable email and a deterministic password derived from a
// short login code + the PIN, then insert the users + family_members rows with
// the service role (bypassing RLS). The child later signs in on their own phone
// with the returned login_code + pin (the app reconstructs the same
// email/password pair -- see AuthService.kidCredentials).
//
// Security: the caller is identified from the VERIFIED JWT, never the body.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const KID_EMAIL_DOMAIN = "kids.thechallenges.app";
// Unambiguous alphabet (no O/0, I/1) so a parent can read the code aloud.
const CODE_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, "Content-Type": "application/json" },
  });
}

function genCode(): string {
  let s = "";
  const bytes = crypto.getRandomValues(new Uint8Array(6));
  for (let i = 0; i < 6; i++) s += CODE_ALPHABET[bytes[i] % CODE_ALPHABET.length];
  return s;
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

    const body = await req.json().catch(() => ({}));
    const name = typeof body.name === "string" ? body.name.trim() : "";
    const pin = typeof body.pin === "string" ? body.pin.trim() : "";
    if (!name) return json({ error: "name_required" }, 400);
    if (!/^\d{4,6}$/.test(pin)) return json({ error: "pin_must_be_4_to_6_digits" }, 400);

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    // The caller must own a family.
    const { data: fam } = await admin
      .from("families")
      .select("id")
      .eq("parent_user_id", user.id)
      .maybeSingle();
    if (!fam) return json({ error: "not_a_parent" }, 403);

    // Allocate a unique login code.
    let code = "";
    for (let attempt = 0; attempt < 10; attempt++) {
      code = genCode();
      const { data: clash } = await admin
        .from("users")
        .select("id")
        .eq("child_login_code", code)
        .maybeSingle();
      if (!clash) break;
      code = "";
    }
    if (!code) return json({ error: "code_alloc_failed" }, 500);

    const email = `kid.${code.toLowerCase()}@${KID_EMAIL_DOMAIN}`;
    const password = `${code}:${pin}`;

    const { data: created, error: cErr } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: { is_child: true, display_name: name },
    });
    if (cErr || !created.user) return json({ error: cErr?.message ?? "create_failed" }, 500);

    const childId = created.user.id;
    const { error: uErr } = await admin.from("users").insert({
      id: childId,
      email,
      display_name: name,
      plan: "free",
      role: "child",
      family_id: fam.id,
      family_role: "child",
      is_child_account: true,
      child_login_code: code,
    });
    if (uErr) {
      await admin.auth.admin.deleteUser(childId);
      return json({ error: uErr.message }, 500);
    }

    const { error: mErr } = await admin.from("family_members").insert({
      family_id: fam.id,
      child_user_id: childId,
    });
    if (mErr) {
      await admin.from("users").delete().eq("id", childId);
      await admin.auth.admin.deleteUser(childId);
      return json({ error: mErr.message }, 500);
    }

    return json({ login_code: code, user_id: childId });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
