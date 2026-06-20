-- Weekly leaderboard rewards become AUTOMATIC streak freezes, distributed every
-- Monday by pg_cron instead of being claimed manually. Global top 3 by current
-- streak (tie-break: total completed) among everyone active last ISO week:
--   rank 1 -> 3 freezes
--   rank 2 -> 2 freezes
--   rank 3 -> 1 freeze
-- Granted into users.bonus_freezes (the freeze wallet). Idempotent per
-- (user_id, iso_week) via leaderboard_rewards, so re-running a Monday (or a
-- manual call) never double-grants. New reward codes: 'freeze3'|'freeze2'|'freeze1'.

-- 1. Distribution job ---------------------------------------------------------
create or replace function public.distribute_weekly_leaderboard_rewards()
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_week    text := to_char(now() - interval '7 days', 'IYYY-IW');
  v_granted int := 0;
  r         record;
  v_freezes int;
begin
  for r in
    with cand as (
      -- Everyone who logged at least one qualifying day last ISO week.
      select distinct a.user_id as uid
      from reports rp
      join activities a on a.id = rp.activity_id
      where rp.ai_result in ('approved', 'not_applicable', 'pending')
        and rp.created_at >= date_trunc('week', now() - interval '7 days')
        and rp.created_at <  date_trunc('week', now())
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
    select uid, rnk from ranked where rnk <= 3
  loop
    -- Idempotency: skip anyone already recorded for this week.
    if exists (select 1 from leaderboard_rewards
               where user_id = r.uid and iso_week = v_week) then
      continue;
    end if;

    v_freezes := case r.rnk when 1 then 3 when 2 then 2 when 3 then 1 else 0 end;

    update users set bonus_freezes = bonus_freezes + v_freezes where id = r.uid;

    insert into leaderboard_rewards (user_id, iso_week, rank, reward)
    values (r.uid, v_week, r.rnk, 'freeze' || v_freezes::text)
    on conflict (user_id, iso_week) do nothing;

    v_granted := v_granted + 1;
  end loop;

  return v_granted;
end $$;

-- Server-only: never callable from the client.
revoke execute on function public.distribute_weekly_leaderboard_rewards() from public, anon, authenticated;

-- 2. Claim becomes read-only --------------------------------------------------
-- Rewards are granted by the cron job above, so claim no longer mutates state;
-- it just reports what the user was awarded last week (idempotent, safe to poll).
create or replace function public.claim_leaderboard_reward()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_uid  uuid := auth.uid();
  v_week text := to_char(now() - interval '7 days', 'IYYY-IW');
  v_row  record;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select rank, reward into v_row
  from leaderboard_rewards
  where user_id = v_uid and iso_week = v_week;

  if found then
    return jsonb_build_object(
      'already_claimed', true,           -- already granted automatically
      'rank',            v_row.rank,
      'reward',          v_row.reward);
  end if;

  -- Not in last week's top 3, or Monday distribution has not run yet.
  return jsonb_build_object('already_claimed', false, 'rank', null, 'reward', null);
end $$;

grant execute on function public.claim_leaderboard_reward() to authenticated;
revoke execute on function public.claim_leaderboard_reward() from public, anon;

-- 3. Schedule: every Monday 00:05 UTC -----------------------------------------
-- cron.schedule upserts by name, so re-applying this migration just updates it.
select cron.unschedule('weekly-leaderboard-freezes')
where exists (select 1 from cron.job where jobname = 'weekly-leaderboard-freezes');

select cron.schedule(
  'weekly-leaderboard-freezes',
  '5 0 * * 1',
  $$select public.distribute_weekly_leaderboard_rewards();$$
);
