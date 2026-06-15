-- Live Activity remote push (#20c)
-- Store the per-activity ActivityKit push token so the push-live-activity edge
-- function can drive the Dynamic Island / Lock Screen banner remotely. Nullable:
-- it is set while an activity is running and cleared when it ends.
alter table public.push_tokens
  add column if not exists live_activity_token text,
  add column if not exists live_activity_updated_at timestamptz;

comment on column public.push_tokens.live_activity_token is
  'APNs Live Activity push token (ActivityKit pushType .token). NULL when no activity is running.';
