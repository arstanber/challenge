-- Logs why a user deleted an activity/task. The activities row itself is
-- hard-deleted (and cascades reports), so this table is the only record of
-- the deletion and its reason -- useful for "analyze-failure"-style coaching.
CREATE TABLE IF NOT EXISTS public.activity_deletions (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id      UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  activity_id  UUID NOT NULL,
  title        TEXT NOT NULL,
  type         TEXT NOT NULL,
  reason       TEXT NOT NULL CHECK (char_length(trim(reason)) > 0),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.activity_deletions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "User can manage own activity deletions"
  ON public.activity_deletions FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
