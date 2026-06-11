-- users_plan_check predates the family/max tiers and only allowed
-- 'free' / 'premium'. Widen it to match UserPlan in the app
-- (free / premium / family / max) and the plan-based limits in
-- 20260606_rate_limiter.sql / 20260611_plan_limits.sql.

alter table public.users drop constraint users_plan_check;

alter table public.users add constraint users_plan_check
  check (plan = any (array['free'::text, 'premium'::text, 'family'::text, 'max'::text]));
