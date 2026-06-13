-- Weekly leaderboard rewards: the top 3 by current streak (globally, among
-- everyone who logged at least one qualifying day last week) can claim a prize
-- once per ISO week.
--   rank 1 -> 7 PRO days
--   rank 2 -> 3 PRO days
--   rank 3 -> 1 streak freeze (users.bonus_freezes)
--
-- Idempotent by (user_id, iso_week): the first claim inserts a row and applies
-- the reward; later calls just return the recorded outcome. Ranking is computed
-- at claim time (no cron) -- fine at current scale; the lateral join is the
-- upgrade point if the user base grows.

create table if not exists public.leaderboard_rewards (
  user_id    uuid not null references public.users(id) on delete cascade,
  iso_week   text not null,                 -- 'IYYY-IW', e.g. '2026-24'
  rank       int,                           -- null/0 = participated but unranked
  reward     text,                          -- 'pro7d' | 'pro3d' | 'freeze' | null
  created_at timestamptz not null default now(),
  primary key (user_id, iso_week)
);

alter table public.leaderboard_rewards enable row level security;

drop policy if exists "Read own leaderboard rewards" on public.leaderboard_rewards;
create policy "Read own leaderboard rewards"
  on public.leaderboard_rewards for select
  using (auth.uid() = user_id);

-- Claim (or re-read) last week's reward for the caller.
create or replace function public.claim_leaderboard_reward()
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_week text;
  v_existing record;
  v_rank int;
  v_reward text;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  -- Previous ISO week (UTC boundaries; global leaderboard).
  v_week := to_char(now() - interval '7 days', 'IYYY-IW');

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

  if v_rank = 1 then
    perform grant_pro_days(v_uid, 7);
  elsif v_rank = 2 then
    perform grant_pro_days(v_uid, 3);
  elsif v_rank = 3 then
    update users set bonus_freezes = bonus_freezes + 1 where id = v_uid;
  end if;

  insert into leaderboard_rewards (user_id, iso_week, rank, reward)
  values (v_uid, v_week, coalesce(v_rank, 0), v_reward);

  return jsonb_build_object(
    'already_claimed', false,
    'rank',            v_rank,
    'reward',          v_reward);
end $$;

grant execute on function public.claim_leaderboard_reward() to authenticated;
revoke execute on function public.claim_leaderboard_reward() from public, anon;
