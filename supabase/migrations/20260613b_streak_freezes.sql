-- Server-side streak freezes.
--
-- Until now freezes lived only in the client (UserDefaults gam_spent_freezes)
-- and never actually protected a streak: compute_user_streak had no notion of
-- a frozen day. This migration makes a freeze real -- a frozen date becomes a
-- qualifying day in the global streak engine (Duolingo-style: it counts toward
-- the run length, bridging a missed day).
--
-- Wallet: a user may freeze up to floor(best_streak / 7) + users.bonus_freezes
-- days total; each frozen row spends one. (The legacy client-side achievement
-- component of the wallet is dropped -- the server is now the single source.)
--
-- Per-activity streaks are intentionally NOT affected; freezes are global only.

create table if not exists public.streak_freezes (
  user_id     uuid not null references public.users(id) on delete cascade,
  frozen_date date not null,
  source      text not null default 'manual',
  created_at  timestamptz not null default now(),
  primary key (user_id, frozen_date)
);

alter table public.streak_freezes enable row level security;

drop policy if exists "Read own freezes" on public.streak_freezes;
create policy "Read own freezes"
  on public.streak_freezes for select
  using (auth.uid() = user_id);
-- All writes go through use_streak_freeze (security definer); no direct insert.

-- ============ per-day qualification helper ============
-- True when day D already counts on its own (>= 75% of the recurring roster
-- scheduled that day, min 1), matching compute_user_streak's qual rule.
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

  return v_done >= greatest(1, ceil(0.75 * v_scheduled))::int;
end $$;

revoke execute on function public.day_qualifies(uuid, date) from public, anon, authenticated;

-- ============ streak engine: frozen days qualify ============
-- Identical to 20260612_streak_75_percent.sql but the qual set is unioned with
-- the user's frozen dates, so a freeze bridges a gap in the run.
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
    where coalesce(dn.cnt, 0) >= greatest(1, ceil(0.75 * s.scheduled))::int
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

-- ============ wallet helper ============
-- Spendable freezes = floor(best_streak / 7) + bonus_freezes - already spent.
create or replace function public.freezes_available(p_user_id uuid)
returns int
language plpgsql stable security definer set search_path = public as $$
declare v_best int; v_bonus int; v_used int;
begin
  select best_streak into v_best from compute_user_streak(p_user_id, 3);
  select coalesce(bonus_freezes, 0) into v_bonus from users where id = p_user_id;
  select count(*) into v_used from streak_freezes where user_id = p_user_id;
  return greatest(0, floor(coalesce(v_best, 0) / 7.0)::int + v_bonus - v_used);
end $$;

revoke execute on function public.freezes_available(uuid) from public, anon, authenticated;

-- ============ RPC: spend a freeze ============
-- Freezes a missed day (defaults to yesterday in the user's timezone). Rejects
-- if the day is out of range, already counts, already frozen, or no balance.
create or replace function public.use_streak_freeze(p_date date default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_tz text; v_today date; v_target date; v_avail int;
  g record;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  select coalesce(timezone, 'UTC') into v_tz from users where id = v_uid;
  v_today := (now() at time zone v_tz)::date;
  v_target := coalesce(p_date, v_today - 1);

  if v_target not in (v_today, v_today - 1) then
    raise exception 'can only freeze today or yesterday';
  end if;
  if exists (select 1 from streak_freezes where user_id = v_uid and frozen_date = v_target) then
    raise exception 'day already frozen';
  end if;
  if day_qualifies(v_uid, v_target) then
    raise exception 'day already counts';
  end if;

  v_avail := freezes_available(v_uid);
  if v_avail <= 0 then raise exception 'no freezes available'; end if;

  insert into streak_freezes (user_id, frozen_date, source)
  values (v_uid, v_target, 'manual');

  select * into g from compute_user_streak(v_uid, 3);
  return jsonb_build_object(
    'global_current', g.current_streak,
    'global_best',    g.best_streak,
    'today_count',    g.today_count,
    'frozen_date',    v_target,
    'freezes_left',   v_avail - 1);
end $$;

grant execute on function public.use_streak_freeze(date) to authenticated;
revoke execute on function public.use_streak_freeze(date) from public, anon;

-- ============ refresh_my_streaks: expose the wallet ============
-- Adds two backward-compatible keys: freezes_available and yesterday_freezable
-- (true when yesterday is missed, unfrozen, and the user has balance).
create or replace function public.refresh_my_streaks()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_tz text; v_today date; v_yesterday date;
  g record; a record; s record;
  acts jsonb := '[]'::jsonb;
  v_avail int; v_yest_freezable boolean;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  select coalesce(timezone, 'UTC') into v_tz from users where id = v_uid;
  v_today := (now() at time zone v_tz)::date;
  v_yesterday := v_today - 1;

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

  v_avail := freezes_available(v_uid);
  v_yest_freezable := v_avail > 0
    and not day_qualifies(v_uid, v_yesterday)
    and not exists (select 1 from streak_freezes where user_id = v_uid and frozen_date = v_yesterday);

  return jsonb_build_object(
    'global_current',      g.current_streak,
    'global_best',         g.best_streak,
    'today_count',         g.today_count,
    'activities',          acts,
    'freezes_available',   v_avail,
    'yesterday_freezable', v_yest_freezable);
end $$;

grant execute on function public.refresh_my_streaks() to authenticated;
