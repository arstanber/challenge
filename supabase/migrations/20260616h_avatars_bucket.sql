-- Avatars storage bucket for the profile page.
--
-- Public-read (object URLs are stored in users.avatar_url and shown across the
-- app), but each user may only write under their own <user_id>/... prefix.
-- Mirrors the "reports" bucket's per-user-folder pattern.

insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

-- Public read of avatar objects (URLs are shared in leaderboards/family lists).
drop policy if exists "Public read avatars" on storage.objects;
create policy "Public read avatars" on storage.objects
  for select using (bucket_id = 'avatars');

-- A user can upload/replace/delete only files under their own id prefix.
drop policy if exists "Users write own avatar" on storage.objects;
create policy "Users write own avatar" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Users update own avatar" on storage.objects;
create policy "Users update own avatar" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "Users delete own avatar" on storage.objects;
create policy "Users delete own avatar" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
