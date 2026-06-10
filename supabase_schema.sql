-- Challenge App — Database Schema
-- Run this in Supabase Dashboard → SQL Editor

-- Enable UUID extension (already enabled by default)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ────────────────────────────────────────────────────────
-- USERS
-- ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.users (
  id         UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email      TEXT NOT NULL,
  avatar_url TEXT,
  plan       TEXT NOT NULL DEFAULT 'free' CHECK (plan IN ('free', 'premium')),
  role       TEXT NOT NULL DEFAULT 'individual' CHECK (role IN ('individual', 'parent', 'child')),
  family_id  UUID,
  -- IANA timezone identifier, upserted by the app on launch. Used for day bucketing in streaks and reminders.
  timezone   TEXT NOT NULL DEFAULT 'UTC',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can read own profile"
  ON public.users FOR SELECT
  USING (auth.uid() = id);

CREATE POLICY "Users can update own profile"
  ON public.users FOR UPDATE
  USING (auth.uid() = id);

CREATE POLICY "Users can insert own profile"
  ON public.users FOR INSERT
  WITH CHECK (auth.uid() = id);

-- ────────────────────────────────────────────────────────
-- FAMILIES
-- ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.families (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  parent_user_id  UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  invite_code     TEXT NOT NULL UNIQUE,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.families ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Parent can manage own family"
  ON public.families FOR ALL
  USING (auth.uid() = parent_user_id);

CREATE POLICY "Anyone can read family by invite code"
  ON public.families FOR SELECT
  USING (true);

-- ────────────────────────────────────────────────────────
-- FAMILY MEMBERS
-- ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.family_members (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  family_id     UUID NOT NULL REFERENCES public.families(id) ON DELETE CASCADE,
  child_user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  joined_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (family_id, child_user_id)
);

ALTER TABLE public.family_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Family members visible to parent and child"
  ON public.family_members FOR SELECT
  USING (
    auth.uid() = child_user_id
    OR auth.uid() IN (
      SELECT parent_user_id FROM public.families WHERE id = family_id
    )
  );

CREATE POLICY "Child can join family"
  ON public.family_members FOR INSERT
  WITH CHECK (auth.uid() = child_user_id);

-- ────────────────────────────────────────────────────────
-- ACTIVITIES
-- ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.activities (
  id              UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  assigned_by     UUID REFERENCES public.users(id),
  title           TEXT NOT NULL,
  description     TEXT NOT NULL DEFAULT '',
  type            TEXT NOT NULL CHECK (type IN ('challenge', 'goal', 'task', 'habit', 'assignment')),
  condition       TEXT,
  frequency       TEXT NOT NULL DEFAULT 'daily' CHECK (frequency IN ('once', 'daily', 'weekly', 'custom')),
  deadline        TIMESTAMPTZ,
  reminder_time   TIMESTAMPTZ,
  status          TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'completed', 'failed')),
  streak_current  INT NOT NULL DEFAULT 0,
  streak_best     INT NOT NULL DEFAULT 0,
  goal_progress   DOUBLE PRECISION NOT NULL DEFAULT 0,
  goal_target     DOUBLE PRECISION,
  -- ISO weekdays (1=Mon..7=Sun) the activity is scheduled on. NULL/empty = every day.
  schedule_days   SMALLINT[] CHECK (schedule_days IS NULL OR (schedule_days <@ ARRAY[1,2,3,4,5,6,7]::SMALLINT[] AND array_length(schedule_days, 1) >= 1)),
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.activities ENABLE ROW LEVEL SECURITY;

CREATE POLICY "User can manage own activities"
  ON public.activities FOR ALL
  USING (auth.uid() = user_id OR auth.uid() = assigned_by);

CREATE POLICY "Parent can read child activities"
  ON public.activities FOR SELECT
  USING (
    user_id IN (
      SELECT fm.child_user_id
      FROM public.family_members fm
      JOIN public.families f ON fm.family_id = f.id
      WHERE f.parent_user_id = auth.uid()
    )
  );

-- ────────────────────────────────────────────────────────
-- REPORTS
-- ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.reports (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  activity_id    UUID NOT NULL REFERENCES public.activities(id) ON DELETE CASCADE,
  photo_url      TEXT,
  comment        TEXT,
  ai_result      TEXT NOT NULL DEFAULT 'not_applicable' CHECK (ai_result IN ('approved', 'rejected', 'pending', 'not_applicable', 'excused')),
  ai_explanation TEXT,
  progress_value DOUBLE PRECISION,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

CREATE POLICY "User can manage reports for own activities"
  ON public.reports FOR ALL
  USING (
    activity_id IN (
      SELECT id FROM public.activities WHERE user_id = auth.uid()
    )
  );

CREATE POLICY "Parent can read child reports"
  ON public.reports FOR SELECT
  USING (
    activity_id IN (
      SELECT a.id FROM public.activities a
      JOIN public.family_members fm ON a.user_id = fm.child_user_id
      JOIN public.families f ON fm.family_id = f.id
      WHERE f.parent_user_id = auth.uid()
    )
  );

-- ────────────────────────────────────────────────────────
-- PUSH TOKENS
-- ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.push_tokens (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE UNIQUE,
  apns_token  TEXT NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.push_tokens ENABLE ROW LEVEL SECURITY;

CREATE POLICY "User can manage own push token"
  ON public.push_tokens FOR ALL
  USING (auth.uid() = user_id);

-- ────────────────────────────────────────────────────────
-- STORAGE BUCKET: reports
-- ────────────────────────────────────────────────────────
-- Run separately in Supabase Dashboard → Storage → New bucket → "reports" (public)
-- Or via SQL:
INSERT INTO storage.buckets (id, name, public)
VALUES ('reports', 'reports', true)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "Authenticated users can upload to reports"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'reports' AND auth.role() = 'authenticated');

CREATE POLICY "Public read access for reports"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'reports');

CREATE POLICY "User can delete own report files"
  ON storage.objects FOR DELETE
  USING (bucket_id = 'reports' AND auth.uid()::text = (storage.foldername(name))[1]);
