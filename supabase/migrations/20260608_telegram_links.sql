-- Telegram bot integration: link a Telegram chat to an app account so the user
-- can create tasks, submit photo proof, and receive notifications via the bot.

-- Permanent link between an app user and their Telegram chat.
-- Written/read ONLY by the telegram-webhook / telegram-notify Edge Functions
-- via the service_role key (same pattern as connector_tokens).
create table if not exists public.telegram_links (
    user_id    uuid        primary key references auth.users(id) on delete cascade,
    chat_id    bigint      not null unique,
    username   text,
    linked_at  timestamptz not null default now()
);

alter table public.telegram_links enable row level security;
revoke all on public.telegram_links from anon, authenticated;

-- Short-lived one-time codes the app generates so the user can link their
-- Telegram account by sending "/start <code>" to the bot. The owning user can
-- create and read their own codes; the webhook (service_role) consumes them.
create table if not exists public.telegram_link_codes (
    code       text        primary key,
    user_id    uuid        not null references auth.users(id) on delete cascade,
    created_at timestamptz not null default now(),
    expires_at timestamptz not null
);

alter table public.telegram_link_codes enable row level security;

create policy "select_own_codes" on public.telegram_link_codes
    for select using (user_id = auth.uid());

create policy "insert_own_codes" on public.telegram_link_codes
    for insert with check (user_id = auth.uid());

create policy "delete_own_codes" on public.telegram_link_codes
    for delete using (user_id = auth.uid());

-- telegram_links has no client-facing policies (service_role only), so the app
-- needs narrow, security-definer windows to read/clear its own link.

create or replace function public.telegram_link_status()
returns table(username text, linked_at timestamptz)
language sql
security definer
set search_path = public
as $$
    select username, linked_at from public.telegram_links where user_id = auth.uid();
$$;

grant execute on function public.telegram_link_status() to authenticated;

create or replace function public.telegram_unlink()
returns void
language sql
security definer
set search_path = public
as $$
    delete from public.telegram_links where user_id = auth.uid();
$$;

grant execute on function public.telegram_unlink() to authenticated;
