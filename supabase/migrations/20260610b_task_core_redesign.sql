-- Task core redesign: schedule_days, user timezone, unified streak engine.
--
-- 1. activities.schedule_days  smallint[] of ISO weekdays (1 = Monday ... 7 = Sunday).
--    NULL or empty = every day (matches pre-existing behavior; no backfill).
-- 2. users.timezone            IANA identifier, default 'UTC'. All server-side day
--    bucketing uses (created_at at time zone u.timezone)::date.
-- 3. Single streak algorithm: compute_activity_streak / compute_user_streak.
--    A trigger on reports keeps activities.streak_current/streak_best fresh on writes;
--    refresh_my_streaks() recomputes on read and self-heals the columns.
-- 4. get_leaderboard rewritten to reuse compute_user_streak (same signature/shape).
--
-- Qualifying-report rule (used everywhere):
--   a day is "done" if a report exists with ai_result in ('approved','not_applicable','pending');
--   'rejected' never counts; 'excused' is forgiving -- neither extends nor breaks a run;
--   today without a report does not break the run yet.

-- ============ 1. schedule_days ============

alter table public.activities add column if not exists schedule_days smallint[]
  check (schedule_days is null or (schedule_days <@ array[1,2,3,4,5,6,7]::smallint[]
         and array_length(schedule_days, 1) >= 1));

comment on column public.activities.schedule_days is
  'ISO weekdays (1=Mon..7=Sun) the activity is scheduled on. NULL/empty = every day.';

-- ============ 2. user timezone ============

alter table public.users add column if not exists timezone text not null default 'UTC';

comment on column public.users.timezone is
  'IANA timezone identifier, upserted by the app on launch. Used for day bucketing in streaks and reminders.';

-- ============ 3. index for streak queries ============

create index if not exists idx_reports_activity_created
  on public.reports (activity_id, created_at);

-- ============ 4. streak engine ============

-- Per-activity streak, schedule-aware: off-days are invisible to the run.
create or replace function public.compute_activity_streak(p_activity_id uuid)
returns table (current_streak int, best_streak int)
language plpgsql stable security definer set search_path = public as $$
declare
  v_tz text; v_days smallint[]; v_today date; v_start date;
  v_done date[]; v_excused date[];
  d date; run int := 0; best int := 0;
begin
  select coalesce(u.timezone, 'UTC'), a.schedule_days into v_tz, v_days
  from activities a join users u on u.id = a.user_id
  where a.id = p_activity_id;
  if not found then
    return query select 0, 0; return;
  end if;

  v_today := (now() at time zone v_tz)::date;

  select coalesce(array_agg(distinct day), '{}') into v_done from (
    select (created_at at time zone v_tz)::date as day from reports
    where activity_id = p_activity_id
      and ai_result in ('approved', 'not_applicable', 'pending')
  ) s;
  select coalesce(array_agg(distinct day), '{}') into v_excused from (
    select (created_at at time zone v_tz)::date as day from reports
    where activity_id = p_activity_id and ai_result = 'excused'
  ) s;

  if array_length(v_done, 1) is null and array_length(v_excused, 1) is null then
    return query select 0, 0; return;
  end if;

  v_start := greatest(
    least(coalesce((select min(x) from unnest(v_done) x), v_today),
          coalesce((select min(x) from unnest(v_excused) x), v_today)),
    v_today - 400);

  for d in select generate_series(v_start, v_today, interval '1 day')::date loop
    if v_days is not null and array_length(v_days, 1) > 0
       and not (extract(isodow from d)::int = any(v_days)) then
      continue;                            -- off-day: invisible to the streak
    end if;
    if d = any(v_done) then
      run := run + 1; best := greatest(best, run);
    elsif d = any(v_excused) then
      null;                                -- forgiven: hold the run
    elsif d = v_today then
      null;                                -- today still in progress: don't break yet
    else
      run := 0;                            -- scheduled day missed
    end if;
  end loop;
  return query select run, best;
end $$;

revoke execute on function public.compute_activity_streak(uuid) from public, anon, authenticated;

-- Global user streak: qualifying day = >= p_min DISTINCT activities done that day.
create or replace function public.compute_user_streak(p_user_id uuid, p_min int default 3)
returns table (current_streak int, best_streak int, today_count int)
language plpgsql stable security definer set search_path = public as $$
declare v_tz text; v_today date;
begin
  select coalesce(timezone, 'UTC') into v_tz from users where id = p_user_id;
  if not found then v_tz := 'UTC'; end if;
  v_today := (now() at time zone v_tz)::date;
  return query
  with day_counts as (
    select (r.created_at at time zone v_tz)::date as day,
           count(distinct r.activity_id) as cnt
    from reports r
    join activities a on a.id = r.activity_id
    where a.user_id = p_user_id
      and r.ai_result in ('approved', 'not_applicable', 'pending')
      and r.created_at > now() - interval '400 days'
    group by 1
  ),
  qual as (select day from day_counts where cnt >= p_min),
  ranked as (select day, row_number() over (order by day desc) as rn from qual),
  grp as (select day, (day + rn * interval '1 day')::date as g from ranked),
  runs as (select g, count(*) as len, max(day) as last_day from grp group by g)
  select
    coalesce((select len from runs where last_day >= v_today - 1
              order by last_day desc limit 1), 0)::int,
    coalesce((select max(len) from runs), 0)::int,
    coalesce((select cnt from day_counts where day = v_today), 0)::int;
end $$;

revoke execute on function public.compute_user_streak(uuid, int) from public, anon, authenticated;

-- Trigger: keep per-activity columns fresh on any report write.
-- AFTER so it never conflicts with the BEFORE protect_ai_verdict trigger.
-- DELETE matters for the app's "undo today"; UPDATE of ai_result matters because
-- verify-report sets the verdict via UPDATE.
create or replace function public.touch_activity_streak()
returns trigger language plpgsql security definer set search_path = public as $$
declare v_aid uuid; v_cur int; v_best int;
begin
  v_aid := coalesce(new.activity_id, old.activity_id);
  select cs.current_streak, cs.best_streak into v_cur, v_best
  from compute_activity_streak(v_aid) cs;
  update activities
  set streak_current = v_cur,
      streak_best    = greatest(coalesce(streak_best, 0), v_best)
  where id = v_aid;
  return coalesce(new, old);
end $$;

revoke execute on function public.touch_activity_streak() from public, anon, authenticated;

drop trigger if exists trg_reports_streak on public.reports;
create trigger trg_reports_streak
  after insert or delete or update of ai_result on public.reports
  for each row execute function public.touch_activity_streak();

-- App-facing RPC: recompute, self-heal columns, return everything in one round trip.
create or replace function public.refresh_my_streaks()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  g record; a record; s record;
  acts jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  select * into g from compute_user_streak(v_uid, 3);
  for a in
    select act.id from activities act
    where act.user_id = v_uid and act.status = 'active'
    limit 100
  loop
    select * into s from compute_activity_streak(a.id);
    update activities
    set streak_current = s.current_streak,
        streak_best    = greatest(coalesce(streak_best, 0), s.best_streak)
    where id = a.id;
    acts := acts || jsonb_build_object(
      'id', a.id,
      'streak_current', s.current_streak,
      'streak_best', (select streak_best from activities where id = a.id));
  end loop;
  return jsonb_build_object(
    'global_current', g.current_streak,
    'global_best',    g.best_streak,
    'today_count',    g.today_count,
    'activities',     acts);
end $$;

grant execute on function public.refresh_my_streaks() to authenticated;
revoke execute on function public.refresh_my_streaks() from public, anon;

-- ============ 5. leaderboard rewritten on top of compute_user_streak ============
-- Same signature and return shape as 20260605_leaderboard.sql; the inline UTC
-- streak CTE is replaced by the canonical engine (per-user timezone, distinct
-- activities per day, rejected excluded).

create or replace function get_leaderboard(p_user_id uuid)
returns table (
    rank            bigint,
    user_id         uuid,
    email           text,
    streak_current  int,
    streak_best     int,
    total_completed bigint
)
language plpgsql
security definer
set search_path = public
as $$
declare
    v_family_id uuid;
begin
    select u.family_id into v_family_id from users u where u.id = p_user_id;

    return query
    with candidate_ids as (
        select u.id
        from   users u
        where  (v_family_id is not null and u.family_id = v_family_id)
           or  u.id = p_user_id
        union
        select fm.child_user_id
        from   family_members fm
        where  v_family_id is not null and fm.family_id = v_family_id
    ),
    streak_data as (
        select ci.id as uid,
               s.current_streak,
               greatest(
                 s.best_streak,
                 coalesce((select max(act.streak_best) from activities act
                           where act.user_id = ci.id), 0)
               ) as best_streak
        from candidate_ids ci
        cross join lateral compute_user_streak(ci.id, 3) s
    ),
    completed as (
        select a.user_id as uid, count(*) as total_completed
        from activities a
        where a.status = 'completed'
          and a.user_id in (select id from candidate_ids)
        group by a.user_id
    )
    select
        rank() over (order by coalesce(s.current_streak, 0) desc,
                              coalesce(c.total_completed, 0) desc)::bigint,
        u.id,
        u.email,
        coalesce(s.current_streak, 0)::int,
        coalesce(s.best_streak, 0)::int,
        coalesce(c.total_completed, 0)
    from candidate_ids ci
    join users u on u.id = ci.id
    left join streak_data s on s.uid = ci.id
    left join completed c on c.uid = ci.id
    order by 1
    limit 50;
end;
$$;

grant execute on function get_leaderboard(uuid) to authenticated;
