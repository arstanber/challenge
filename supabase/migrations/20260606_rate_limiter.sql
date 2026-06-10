-- ai_usage: tracks per-user per-feature monthly usage
create table if not exists ai_usage (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid references users(id) on delete cascade not null,
  feature    text not null,
  month      text not null,  -- 'YYYY-MM'
  count      int  not null default 0,
  unique(user_id, feature, month)
);

-- Users can only read their own usage (for UI display)
alter table ai_usage enable row level security;
create policy "select_own" on ai_usage for select using (user_id = auth.uid());
-- No insert/update/delete from client — only the service-role function below can write

-- Atomic check-and-increment. Called with service_role key only, never exposed to client.
-- Returns: { allowed: bool, remaining: int, limit: int }
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
      case v_plan when 'free' then 5 when 'premium' then 15 when 'family' then 20 when 'max' then 30 else 0 end
    when 'parse-tasks-group' then   -- parse-tasks + parse-schedule + categorize share one bucket
      case v_plan when 'free' then 1 when 'premium' then 5  when 'family' then 8  when 'max' then 10 else 0 end
    when 'coach-group' then         -- morning-brief + analyze-failure + split-goal share one bucket
      case v_plan when 'free' then 1 when 'premium' then 5  when 'family' then 8  when 'max' then 12 else 0 end
    when 'plan-goal' then
      case v_plan when 'free' then 3 when 'premium' then 10 when 'family' then 10 when 'max' then 20 else 0 end
    else 0
  end;

  -- 3. Get current count this month
  select coalesce(count, 0) into v_count
  from ai_usage
  where user_id = p_user_id and feature = p_feature and month = p_month;

  -- 4. Over limit — reject without incrementing
  if v_count >= v_limit then
    return jsonb_build_object('allowed', false, 'remaining', 0, 'limit', v_limit);
  end if;

  -- 5. Atomically increment (upsert)
  insert into ai_usage(user_id, feature, month, count)
    values (p_user_id, p_feature, p_month, 1)
  on conflict (user_id, feature, month)
  do update set count = ai_usage.count + 1;

  return jsonb_build_object('allowed', true, 'remaining', v_limit - v_count - 1, 'limit', v_limit);
end;
$$;

-- Only the postgres superuser (service_role) can call this function.
-- Revoke from anon and authenticated so no one can call it directly via PostgREST.
revoke execute on function check_and_increment_usage(uuid, text, text) from anon, authenticated;
