-- activity_deletions is an audit log -- the only record left after an activity
-- is hard-deleted. The original FOR ALL policy let users UPDATE and DELETE their
-- own audit rows, defeating the point. Replace it with append-only access:
-- users may INSERT and SELECT their own rows, nothing else.

drop policy if exists "User can manage own activity deletions" on public.activity_deletions;

create policy "User can read own activity deletions"
  on public.activity_deletions for select
  using (auth.uid() = user_id);

create policy "User can insert own activity deletions"
  on public.activity_deletions for insert
  with check (auth.uid() = user_id);
