-- distribute_weekly_leaderboard_rewards now returns the freshly-granted winners
-- as jsonb (so the leaderboard-weekly edge function can push them), and the
-- Monday cron routes through that function instead of calling the RPC directly.
-- Return shape: [{ "user_id": uuid, "rank": int, "freezes": int }, ...] -- empty
-- on re-run (idempotent), so pushes only ever fire once per winner per week.

drop function if exists public.distribute_weekly_leaderboard_rewards();

create function public.distribute_weekly_leaderboard_rewards()
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_week    text := to_char(now() - interval '7 days', 'IYYY-IW');
  v_winners jsonb := '[]'::jsonb;
  r         record;
  v_freezes int;
begin
  for r in
    with cand as (
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
    if exists (select 1 from leaderboard_rewards
               where user_id = r.uid and iso_week = v_week) then
      continue;
    end if;

    v_freezes := case r.rnk when 1 then 3 when 2 then 2 when 3 then 1 else 0 end;

    update users set bonus_freezes = bonus_freezes + v_freezes where id = r.uid;

    insert into leaderboard_rewards (user_id, iso_week, rank, reward)
    values (r.uid, v_week, r.rnk, 'freeze' || v_freezes::text)
    on conflict (user_id, iso_week) do nothing;

    v_winners := v_winners || jsonb_build_object(
      'user_id', r.uid, 'rank', r.rnk, 'freezes', v_freezes);
  end loop;

  return v_winners;
end $$;

revoke execute on function public.distribute_weekly_leaderboard_rewards() from public, anon, authenticated;

-- Repoint the Monday cron to the edge function (which distributes + pushes).
select cron.unschedule('weekly-leaderboard-freezes')
where exists (select 1 from cron.job where jobname = 'weekly-leaderboard-freezes');

select cron.schedule(
  'weekly-leaderboard-freezes',
  '5 0 * * 1',
  $$
  select net.http_post(
    url := 'https://tvuvfuguxjvzyzsjnepr.supabase.co/functions/v1/leaderboard-weekly',
    headers := '{"Content-Type": "application/json"}'::jsonb,
    body := '{}'::jsonb
  );
  $$
);
