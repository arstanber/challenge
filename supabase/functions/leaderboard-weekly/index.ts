import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { type Lang, pickLang } from "../_shared/i18n.ts";

// Weekly leaderboard distribution + winner push.
//
// Invoked by pg_cron every Monday (see migration). It calls the
// distribute_weekly_leaderboard_rewards() RPC, which grants streak freezes to
// last week's global top 3 (3 / 2 / 1) and returns ONLY the users granted on
// this run (idempotent -- empty on re-run). For each fresh winner it sends an
// APNs push via the send-push function using the service-role key.

const URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

interface Winner {
  user_id: string;
  rank: number;
  freezes: number;
}

const PLACE_RU: Record<number, string> = { 1: "1 место", 2: "2 место", 3: "3 место" };

// Russian plural for "заморозка" (1), "заморозки" (2-4), "заморозок" (5+).
function freezeWordRu(n: number): string {
  const mod10 = n % 10, mod100 = n % 100;
  if (mod10 === 1 && mod100 !== 11) return "заморозку";
  if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) return "заморозки";
  return "заморозок";
}

const PLACE_DE: Record<number, string> = { 1: "1. Platz", 2: "2. Platz", 3: "3. Platz" };
const PLACE_KK: Record<number, string> = { 1: "1-орын", 2: "2-орын", 3: "3-орын" };
const PLACE_FR: Record<number, string> = { 1: "1re place", 2: "2e place", 3: "3e place" };
const PLACE_AR: Record<number, string> = { 1: "المركز الأول", 2: "المركز الثاني", 3: "المركز الثالث" };

// Arabic counts 1 / 2 / 3-10 differently; ranks only ever grant 1-3 freezes.
function freezeWordAr(n: number): string {
  if (n === 1) return "تجميدة واحدة";
  if (n === 2) return "تجميدتين";
  return `${n} تجميدات`;
}

function pushText(w: Winner, lang: Lang): { title: string; body: string } {
  if (lang === "ru") {
    const place = PLACE_RU[w.rank] ?? `#${w.rank}`;
    return {
      title: "🏆 Ты в топе недели!",
      body: `${place} в рейтинге -- тебе начислено ${w.freezes} ${freezeWordRu(w.freezes)} серии 🧊`,
    };
  }
  if (lang === "de") {
    const place = PLACE_DE[w.rank] ?? `#${w.rank}`;
    const freezeWord = w.freezes === 1 ? "Freeze" : "Freezes";
    return {
      title: "🏆 Du gehörst diese Woche zur Spitze!",
      body: `${place} in der Rangliste -- du hast ${w.freezes} Serien-${freezeWord} erhalten 🧊`,
    };
  }
  if (lang === "kk") {
    const place = PLACE_KK[w.rank] ?? `#${w.rank}`;
    return {
      title: "🏆 Сен осы аптаның үздігісің!",
      body: `Рейтингте ${place} -- саған ${w.freezes} серия тоңазытқышы есептелді 🧊`,
    };
  }
  if (lang === "fr") {
    const place = PLACE_FR[w.rank] ?? `#${w.rank}`;
    const freezeWord = w.freezes === 1 ? "gel de série" : "gels de série";
    return {
      title: "🏆 Tu es dans le top de la semaine !",
      body: `${place} au classement -- tu as gagné ${w.freezes} ${freezeWord} 🧊`,
    };
  }
  if (lang === "ar") {
    const place = PLACE_AR[w.rank] ?? `#${w.rank}`;
    return {
      title: "🏆 أنت من الأفضل هذا الأسبوع!",
      body: `${place} في الترتيب -- حصلت على ${freezeWordAr(w.freezes)} للسلسلة 🧊`,
    };
  }
  const place = w.rank === 1 ? "1st place" : w.rank === 2 ? "2nd place" : w.rank === 3 ? "3rd place" : `#${w.rank}`;
  const freezeWord = w.freezes === 1 ? "freeze" : "freezes";
  return {
    title: "🏆 You're a top performer this week!",
    body: `${place} on the leaderboard -- you earned ${w.freezes} streak ${freezeWord} 🧊`,
  };
}

serve(async () => {
  const supabase = createClient(URL, SERVICE_ROLE_KEY);

  const { data, error } = await supabase.rpc("distribute_weekly_leaderboard_rewards");
  if (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 500,
      headers: { "Content-Type": "application/json" },
    });
  }

  const winners: Winner[] = Array.isArray(data) ? data : [];
  let pushed = 0;

  const { data: langRows } = winners.length
    ? await supabase.from("users").select("id, language").in("id", winners.map((w) => w.user_id))
    : { data: [] as { id: string; language: string }[] };
  const langById = new Map((langRows ?? []).map((r): [string, Lang] => [r.id, pickLang(r.language)]));

  for (const w of winners) {
    const lang: Lang = langById.get(w.user_id) ?? "ru";
    const { title, body } = pushText(w, lang);
    try {
      const res = await fetch(`${URL}/functions/v1/send-push`, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          user_id: w.user_id,
          title,
          body,
          data: { type: "leaderboard_reward", rank: String(w.rank) },
        }),
      });
      if (res.ok) pushed++;
    } catch (_e) {
      // A missing push token or transient APNs error must not block other
      // winners -- the freeze is already granted regardless of the push.
    }
  }

  return new Response(JSON.stringify({ ok: true, winners: winners.length, pushed }), {
    headers: { "Content-Type": "application/json" },
  });
});
