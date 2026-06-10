-- Schedules a daily Telegram reminder digest (telegram-reminders Edge Function)
-- via pg_cron + pg_net. The function is internal/service-only (verify_jwt =
-- false, same as telegram-notify) so the cron job can call it with a plain
-- POST — no secrets need to live in the job definition.

create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

select cron.schedule(
  'telegram-daily-reminders',
  '0 8 * * *',  -- 08:00 UTC daily
  $$
  select net.http_post(
    url := 'https://tvuvfuguxjvzyzsjnepr.supabase.co/functions/v1/telegram-reminders',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := '{}'::jsonb
  );
  $$
);
