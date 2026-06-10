-- OAuth tokens for third-party fitness connectors (Strava, Google Fit, Garmin, Whoop, Fitbit).
-- Tokens are written/read ONLY by the connector-oauth Edge Function via the service_role key.
-- RLS is enabled with NO policies, so anon/authenticated clients can never read them.

create table if not exists public.connector_tokens (
    user_id       uuid        not null references auth.users(id) on delete cascade,
    provider      text        not null,
    access_token  text        not null,
    refresh_token text,
    expires_at    timestamptz,
    scope         text,
    created_at    timestamptz not null default now(),
    updated_at    timestamptz not null default now(),
    primary key (user_id, provider)
);

alter table public.connector_tokens enable row level security;

-- Defense in depth: no client role may touch this table directly.
revoke all on public.connector_tokens from anon, authenticated;
