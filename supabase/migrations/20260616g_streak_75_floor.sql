-- Streak threshold: round the 75% rule DOWN instead of up.
--
-- The day-qualifies rule was `done >= ceil(0.75 * scheduled)` (min 1). With
-- ceil, a 2-task day needed 2 and a 3-task day needed 3 -- effectively 100% for
-- small rosters -- so users who completed most of their tasks still saw a 0
-- streak. Switching to floor makes the rule "do the bulk of your tasks":
--   1 task  -> 1   2 tasks -> 1   3 tasks -> 2   4 tasks -> 3   8 tasks -> 6
-- Minimum stays 1 so a single-task day still counts.
--
-- Redefines the two functions that encode the threshold (latest versions live
-- in 20260613b_streak_freezes.sql). Everything else (freeze union, grace day,
-- qualifying ai_result set) is unchanged. The Swift mirror
-- (Constants.dailyStreakGoal / TaskEngine fallback) is updated to .rounded(.down)
-- in the same change -- keep them in sync.

create or replace function public.day_qualifies(p_user_id uuid, p_day date)
returns boolean
language plpgsql stable security definer set search_path = public as $$
declare
  v_tz text; v_scheduled int; v_done int;
begin
  select coalesce(timezone, 'UTC') into v_tz from users where id = p_user_id;
  if not found then return false; end if;

  select count(a.id) into v_scheduled
  from activities a
  where a.user_id = p_user_id
    and a.status = 'active'
    and a.frequency <> 'once'
    and (a.created_at at time zone v_tz)::date <= p_day
    and (a.schedule_days is null
         or array_length(a.schedule_days, 1) is null
         or extract(isodow from p_day)::smallint = any(a.schedule_days));

  select count(distinct r.activity_id) into v_done
  from reports r
  join activities a on a.id = r.activity_id
  where a.user_id = p_user_id
    and r.ai_result in ('approved', 'not_applicable', 'pending')
    and (r.created_at at time zone v_tz)::date = p_day;

  return v_done >= greatest(1, floor(0.75 * v_scheduled))::int;
end $$;

revoke execute on function public.day_qualifies(uuid, date) from public, anon, authenticated;

create or replace function public.compute_user_streak(p_user_id uuid, p_min int default 3)
returns table (current_streak int, best_streak int, today_count int)
language plpgsql stable security definer set search_path = public as $$
declare v_tz text; v_today date; v_start date;
begin
  select coalesce(timezone, 'UTC') into v_tz from users where id = p_user_id;
  if not found then v_tz := 'UTC'; end if;
  v_today := (now() at time zone v_tz)::date;

  return query
  with done as (
    select (r.created_at at time zone v_tz)::date as day,
           count(distinct r.activity_id) as cnt
    from reports r
    join activities a on a.id = r.activity_id
    where a.user_id = p_user_id
      and r.ai_result in ('approved', 'not_applicable', 'pending')
      and r.created_at > now() - interval '400 days'
    group by 1
  ),
  days as (
    select d::date as day
    from generate_series(
      greatest(coalesce((select min(dn.day) from done dn), v_today), v_today - 400),
      v_today, interval '1 day') d
  ),
  sched as (
    select dd.day, count(a.id) as scheduled
    from days dd
    left join activities a
      on a.user_id = p_user_id
     and a.status = 'active'
     and a.frequency <> 'once'
     and (a.created_at at time zone v_tz)::date <= dd.day
     and (a.schedule_days is null
          or array_length(a.schedule_days, 1) is null
          or extract(isodow from dd.day)::smallint = any(a.schedule_days))
    group by dd.day
  ),
  qual as (
    select s.day
    from sched s
    left join done dn on dn.day = s.day
    where coalesce(dn.cnt, 0) >= greatest(1, floor(0.75 * s.scheduled))::int
    union
    select f.frozen_date
    from streak_freezes f
    where f.user_id = p_user_id
      and f.frozen_date between v_today - 400 and v_today
  ),
  ranked as (select q.day, row_number() over (order by q.day desc) as rn from qual q),
  grp as (select r.day, (r.day + r.rn * interval '1 day')::date as g from ranked r),
  runs as (select g, count(*) as len, max(grp.day) as last_day from grp group by g)
  select
    coalesce((select len from runs where last_day >= v_today - 1
              order by last_day desc limit 1), 0)::int,
    coalesce((select max(len) from runs), 0)::int,
    coalesce((select dn.cnt from done dn where dn.day = v_today), 0)::int;
end $$;

revoke execute on function public.compute_user_streak(uuid, int) from public, anon, authenticated;
