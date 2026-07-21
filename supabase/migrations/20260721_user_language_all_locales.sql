-- ============ users.language: create if missing, widen to all locales ============
-- Two problems this fixes.
--
-- 1. The column was never applied to the live database (tvuvfuguxjvzyzsjnepr).
--    20260620f_user_language.sql defines it, but the deployed schema has no
--    such column, so every launch logs:
--      PGRST204 "Could not find the 'language' column of 'users'"
--    from AuthService.syncLanguage. The write is fire-and-forget, so nothing
--    breaks loudly -- but users.language never gets written, and every
--    server-composed push / AI response falls back to a default language.
--
-- 2. 20260620f constrains the column to ('en','ru'), which predates the 6-language
--    rollout. AppLanguage.supported is now en/ru/de/kk/fr/ar and the client writes
--    that bare code verbatim. Applying 20260620f alone would swap the PGRST204 for
--    a 23514 check violation for exactly the non-RU users the rollout targeted.
--
-- Idempotent and order-independent: on a fresh replay 20260620f runs first and
-- creates the column as NOT NULL DEFAULT 'ru', so we explicitly relax both here
-- rather than relying on the add-column below.

-- Create only if 20260620f has not already run (e.g. the live database, where it
-- never was applied). Nullable, no default -- the client fills it on login and
-- the server falls back when null.
alter table public.users
  add column if not exists language text;

-- Relax the shape 20260620f would have created. No-ops when the column was just
-- created above.
alter table public.users
  alter column language drop default;

alter table public.users
  alter column language drop not null;

-- Replace the ('en','ru') constraint with one covering every AppLanguage.supported
-- code. NULL passes a CHECK by default, which is what we want for un-synced rows.
-- Dropped by discovered name: the inline CHECK in 20260620f is system-named, and
-- that name is not guaranteed across environments.
do $$
declare
  c text;
begin
  for c in
    select con.conname
    from pg_constraint con
    join pg_class rel on rel.oid = con.conrelid
    join pg_namespace ns on ns.oid = rel.relnamespace
    where ns.nspname = 'public'
      and rel.relname = 'users'
      and con.contype = 'c'
      and pg_get_constraintdef(con.oid) ilike '%language%'
  loop
    execute format('alter table public.users drop constraint %I', c);
  end loop;
end $$;

alter table public.users
  add constraint users_language_check
  check (language in ('en', 'ru', 'de', 'kk', 'fr', 'ar'));

-- Recreated because 20260620f may never have run here. Unchanged in behaviour:
-- narrow security-definer lookup so a client can resolve ANOTHER user's language
-- (e.g. a duel opponent) for a cross-user push -- users RLS only allows reading
-- family members. Returns only the language code, nothing else from the row.
--
-- NOTE: this coalesces to 'ru' while the edge functions' pickLang() falls back to
-- 'en' for null. Left as-is to keep this migration to the schema fix; the two
-- fallbacks should be reconciled deliberately.
create or replace function public.get_user_language(p_user_id uuid)
returns text language sql security definer set search_path = public as $$
  select coalesce(language, 'ru') from users where id = p_user_id;
$$;

grant execute on function public.get_user_language(uuid) to authenticated;
