-- Security hardening (2026-06-10), from Supabase security advisor findings:
--   1. Public bucket "reports" allowed listing ALL user photos via the storage API.
--   2. check_and_increment_usage was executable by anon/authenticated (the revoke
--      from 20260606_rate_limiter.sql was lost when the function was re-created),
--      letting anyone burn another user's monthly AI quota.
--   3. telegram_* RPCs were executable by anon (harmless via auth.uid(), but
--      there is no reason to expose them unauthenticated).
--   4. Clients could write ai_result/ai_explanation directly, faking AI approval.
--      The verdict is now written server-side by the verify-report edge function.

-- ── 1. Storage: public object URLs keep working, but listing the bucket is no longer possible
drop policy if exists "Public read reports" on storage.objects;

-- ── 2. Quota counter: service_role only (edge functions call it with the service key)
revoke execute on function public.check_and_increment_usage(uuid, text, text)
  from public, anon, authenticated;

-- ── 3. Telegram RPCs: signed-in users only (the app calls them as `authenticated`)
revoke execute on function public.telegram_link_status() from public, anon;
revoke execute on function public.telegram_unlink() from public, anon;

-- ── 4. AI verdict columns are read-only for clients
create or replace function public.protect_ai_verdict()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  -- service_role (edge functions) and direct admin connections are exempt
  if coalesce(auth.role(), '') = 'service_role'
     or session_user in ('postgres', 'supabase_admin') then
    return new;
  end if;

  if tg_op = 'INSERT' then
    if new.ai_result in ('approved', 'excused') then
      raise exception 'ai_result % cannot be set by the client', new.ai_result;
    end if;
  elsif tg_op = 'UPDATE' then
    if new.ai_result is distinct from old.ai_result
       or new.ai_explanation is distinct from old.ai_explanation then
      raise exception 'AI verdict fields are read-only for clients';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists trg_protect_ai_verdict on public.reports;
create trigger trg_protect_ai_verdict
  before insert or update on public.reports
  for each row execute function public.protect_ai_verdict();

-- Trigger function should not be exposed through PostgREST at all
revoke execute on function public.protect_ai_verdict() from public, anon, authenticated;
