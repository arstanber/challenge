-- ============ Per-user language (EN/RU) ============
-- Auto-detected from device locale, synced like users.timezone (see
-- AuthService.syncLanguage). Drives which language server-composed pushes
-- and AI responses (leaderboard rewards, family leave requests, Telegram
-- bot, AI coach, photo verification) are written in.
--
-- Default 'ru' because every existing row predates this column and belongs
-- to the current (Russian) user base; corrected within one app session via
-- sync, same as timezone.
alter table public.users
  add column if not exists language text not null default 'ru'
  check (language in ('en', 'ru'));

-- Narrow lookup so a client can resolve ANOTHER user's language (e.g. a duel
-- opponent) for a cross-user push -- users RLS only allows reading family
-- members, so a plain select would be blocked for non-family recipients.
-- Returns only the language code, nothing else from the row.
create or replace function public.get_user_language(p_user_id uuid)
returns text language sql security definer set search_path = public as $$
  select coalesce(language, 'ru') from users where id = p_user_id;
$$;

grant execute on function public.get_user_language(uuid) to authenticated;
