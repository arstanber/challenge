-- Fix a double-grant race in claim_leaderboard_reward. The previous version
-- checked for an existing row, then later inserted -- so two concurrent calls
-- could both pass the check, both grant the reward (grant_pro_days / bonus
-- freeze applied twice), and the second insert would then fail on the primary
-- key. Claim the (user_id, iso_week) slot atomically FIRST, and only grant the
-- reward if this call actually won the insert.
--
-- (The ISO week is correct as-is: Postgres date_trunc('week', ...) is Monday-
-- based, matching to_char(..., 'IYYY-IW').)

create or replace function public.claim_leaderboard_reward()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_week text;
  v_existing record;
  v_rank int;
  v_reward text;
  v_won int;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  -- Previous ISO week (UTC boundaries; global leaderboard).
  v_week := to_char(now() - interval '7 days', 'IYYY-IW');

  -- Fast path: already claimed.
  select rank, reward into v_existing
  from leaderboard_rewards where user_id = v_uid and iso_week = v_week;
  if found then
    return jsonb_build_object(
      'already_claimed', true,
      'rank',            v_existing.rank,
      'reward',          v_existing.reward);
  end if;

  -- Rank the caller globally among last week's active users.
  with cand as (
    select distinct a.user_id as uid
    from reports r
    join activities a on a.id = r.activity_id
    where r.ai_result in ('approved', 'not_applicable', 'pending')
      and r.created_at >= date_trunc('week', now() - interval '7 days')
      and r.created_at <  date_trunc('week', now())
  ),
  scored as (
    select c.uid,
           s.current_streak,
           coalesce((select count(*) from activities
                     where user_id = c.uid and status = 'completed'), 0) as total_completed
    from cand c
    cross join lateral compute_user_streak(c.uid, 3) s
  ),
  ranked as (
    select uid,
           rank() over (order by current_streak desc, total_completed desc) as rnk
    from scored
  )
  select rnk into v_rank from ranked where uid = v_uid;

  v_reward := case v_rank when 1 then 'pro7d' when 2 then 'pro3d' when 3 then 'freeze' else null end;

  -- Atomically claim the slot. If another call already inserted it, we lose the
  -- race and must NOT grant the reward again.
  insert into leaderboard_rewards (user_id, iso_week, rank, reward)
  values (v_uid, v_week, coalesce(v_rank, 0), v_reward)
  on conflict (user_id, iso_week) do nothing;
  get diagnostics v_won = row_count;

  if v_won = 0 then
    select rank, reward into v_existing
    from leaderboard_rewards where user_id = v_uid and iso_week = v_week;
    return jsonb_build_object(
      'already_claimed', true,
      'rank',            v_existing.rank,
      'reward',          v_existing.reward);
  end if;

  -- We won the insert -> apply the reward exactly once.
  if v_rank = 1 then
    perform grant_pro_days(v_uid, 7);
  elsif v_rank = 2 then
    perform grant_pro_days(v_uid, 3);
  elsif v_rank = 3 then
    update users set bonus_freezes = bonus_freezes + 1 where id = v_uid;
  end if;

  return jsonb_build_object(
    'already_claimed', false,
    'rank',            v_rank,
    'reward',          v_reward);
end $$;

grant execute on function public.claim_leaderboard_reward() to authenticated;
revoke execute on function public.claim_leaderboard_reward() from public, anon;
