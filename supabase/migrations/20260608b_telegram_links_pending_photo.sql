-- Lets the bot remember an in-flight photo (file_id + caption) while the user
-- picks which active challenge it belongs to via an inline keyboard.
alter table public.telegram_links add column if not exists pending_photo jsonb;
