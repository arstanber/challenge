// Child requests to leave their family.
//
// Generates a 6-digit code, stores it (service role) in family_leave_requests,
// and pushes it to the PARENT only. The code is never returned to the child --
// the parent reads it from the push and decides whether to share it, gating the
// child's ability to leave. The child then calls leave_family_with_code(code).
//
// Security: the child is identified from the VERIFIED JWT, never the body.

import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { pickLang } from "../_shared/i18n.ts";

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

function genCode(): string {
  const n = crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000;
  return n.toString().padStart(6, "0");
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

    // The caller must be a child in a family.
    const { data: me } = await admin
      .from("users")
      .select("family_id, display_name, email")
      .eq("id", user.id)
      .maybeSingle();
    if (!me?.family_id) return json({ error: "not_in_family" }, 400);

    const { data: fam } = await admin
      .from("families")
      .select("parent_user_id")
      .eq("id", me.family_id)
      .maybeSingle();
    if (!fam?.parent_user_id) return json({ error: "no_parent" }, 400);

    const { data: parent } = await admin
      .from("users")
      .select("language")
      .eq("id", fam.parent_user_id)
      .maybeSingle();
    const lang = pickLang(parent?.language);

    const code = genCode();
    const { error: upErr } = await admin
      .from("family_leave_requests")
      .upsert({ child_user_id: user.id, code, created_at: new Date().toISOString() });
    if (upErr) return json({ error: upErr.message }, 500);

    // Push the code to the parent (reuse the authenticated send-push function;
    // the child's JWT is a valid authenticated caller). Localized in the
    // PARENT's language -- the push goes to them, not to the child caller.
    const childName = (me.display_name && me.display_name.trim())
      || (me.email ? me.email.split("@")[0] : (lang === "ru" ? "Ребёнок" : "Child"));
    const title = lang === "ru" ? "Запрос на выход из семьи" : "Request to leave the family";
    const body = lang === "ru"
      ? `${childName} хочет выйти из семьи. Код для подтверждения: ${code}. Сообщи его ребёнку, если согласен.`
      : `${childName} wants to leave the family. Confirmation code: ${code}. Share it with them if you agree.`;
    const pushRes = await fetch(`${Deno.env.get("SUPABASE_URL")}/functions/v1/send-push`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: authHeader },
      body: JSON.stringify({ user_id: fam.parent_user_id, title, body }),
    });
    // A missing parent push token is not fatal -- the request row still exists
    // and the parent can read the code elsewhere; report it so the client can
    // tell the child to ask the parent to open the app.
    const pushed = pushRes.ok;

    return json({ ok: true, pushed });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
