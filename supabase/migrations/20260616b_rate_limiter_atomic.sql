-- Fix a quota-bypass race in check_and_increment_usage. The previous version
-- (20260611_plan_limits.sql) read the count, checked it against the limit, then
-- incremented in separate statements -- so two concurrent requests could both
-- pass the check at count = limit - 1 and both increment, exceeding the quota.
--
-- Replace with a single atomic upsert whose ON CONFLICT update only fires while
-- the row is still under the limit (the unique row lock serializes concurrent
-- callers). Limits are kept IDENTICAL to 20260611_plan_limits.sql (the current
-- tiers) -- MUST mirror AIFeature.limit(for:) in the app; change them together.

create or replace function check_and_increment_usage(
  p_user_id uuid,
  p_feature  text,
  p_month    text
) returns jsonb
  language plpgsql
  security definer  -- runs as postgres superuser, bypasses RLS
  set search_path = public
as $$
declare
  v_plan    text;
  v_limit   int;
  v_count   int;
begin
  -- 1. Get the user's subscription plan
  select plan into v_plan from users where id = p_user_id;
  if not found then
    return jsonb_build_object('allowed', false, 'remaining', 0, 'limit', 0);
  end if;

  -- 2. Determine monthly limit for this feature + plan
  v_limit := case p_feature
    when 'verify-report' then
      case v_plan when 'free' then 5 when 'premium' then 30 when 'family' then 30 when 'max' then 100 else 0 end
    when 'parse-tasks-group' then   -- parse-tasks + parse-schedule + categorize share one bucket
      case v_plan when 'free' then 1 when 'premium' then 10 when 'family' then 10 when 'max' then 30 else 0 end
    when 'coach-group' then         -- morning-brief + analyze-failure + split-goal share one bucket
      case v_plan when 'free' then 1 when 'premium' then 10 when 'family' then 10 when 'max' then 30 else 0 end
    when 'plan-goal' then
      case v_plan when 'free' then 3 when 'premium' then 15 when 'family' then 15 when 'max' then 50 else 0 end
    else 0
  end;

  -- Unknown feature/plan, or a zero allowance: reject before touching the table.
  if v_limit <= 0 then
    return jsonb_build_object('allowed', false, 'remaining', 0, 'limit', v_limit);
  end if;

  -- 3. Atomic check-and-increment. The first use inserts count = 1; subsequent
  -- uses increment ONLY while still under the limit. The unique (user, feature,
  -- month) constraint serializes concurrent callers on the same row, so the
  -- WHERE guard cannot be bypassed by a race.
  insert into ai_usage(user_id, feature, month, count)
    values (p_user_id, p_feature, p_month, 1)
  on conflict (user_id, feature, month)
    do update set count = ai_usage.count + 1
    where ai_usage.count < v_limit
  returning count into v_count;

  -- 4. No row returned => the ON CONFLICT update was blocked by the WHERE guard,
  -- i.e. the user is already at the limit this month.
  if v_count is null then
    return jsonb_build_object('allowed', false, 'remaining', 0, 'limit', v_limit);
  end if;

  return jsonb_build_object('allowed', true, 'remaining', v_limit - v_count, 'limit', v_limit);
end;
$$;

-- Only the postgres superuser (service_role) can call this function.
revoke execute on function check_and_increment_usage(uuid, text, text) from anon, authenticated;
