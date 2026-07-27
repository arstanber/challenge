-- Partial counter/timer progress must not count as task completion. Entries
-- live separately from reports; the record_activity_progress RPC creates one
-- qualifying report only when the server-side target is reached.

create table if not exists public.activity_progress_entries (
  id uuid primary key default uuid_generate_v4(),
  activity_id uuid not null references public.activities(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  value double precision not null
    check (value > 0 and value <= 1000000),
  created_at timestamptz not null default now()
);

create index if not exists idx_activity_progress_entries_activity_created
  on public.activity_progress_entries (activity_id, created_at);

create index if not exists idx_activity_progress_entries_user_created
  on public.activity_progress_entries (user_id, created_at);

alter table public.activity_progress_entries enable row level security;

-- The app only reaches this table through narrow RPCs. Keep the raw rows out
-- of the Data API even if public tables are exposed for this project.
revoke all on table public.activity_progress_entries from public, anon, authenticated;

alter table public.reports
  add column if not exists progress_date date;

-- Preserve progress recorded by the first completion-modes client. Those
-- builds wrote every partial increment into reports, which made a partial
-- counter/timer look completed. Reuse each report id so this backfill is
-- idempotent if the migration is replayed in a development environment.
insert into public.activity_progress_entries (
  id,
  activity_id,
  user_id,
  value,
  created_at
)
select r.id,
       r.activity_id,
       a.user_id,
       r.progress_value,
       r.created_at
  from public.reports r
  join public.activities a on a.id = r.activity_id
 where a.completion_mode in ('counter', 'timer')
   and r.progress_value > 0
   and r.progress_value <= 1000000
on conflict (id) do nothing;

-- For recurring activities, retain one report only on local days whose
-- accumulated progress actually reached the target.
with ranked as (
  select r.id,
         (r.created_at at time zone coalesce(u.timezone, 'UTC'))::date as local_date,
         sum(r.progress_value) over (
           partition by r.activity_id,
                        (r.created_at at time zone coalesce(u.timezone, 'UTC'))::date
         ) as day_total,
         row_number() over (
           partition by r.activity_id,
                        (r.created_at at time zone coalesce(u.timezone, 'UTC'))::date
           order by r.created_at desc, r.id
         ) as row_number,
         a.goal_target
    from public.reports r
    join public.activities a on a.id = r.activity_id
    join public.users u on u.id = a.user_id
   where a.completion_mode in ('counter', 'timer')
     and a.frequency <> 'once'
     and r.progress_value is not null
)
update public.reports r
   set progress_value = ranked.day_total,
       progress_date = ranked.local_date
  from ranked
 where r.id = ranked.id
   and ranked.row_number = 1
   and ranked.day_total >= ranked.goal_target;

with ranked as (
  select r.id,
         sum(r.progress_value) over (
           partition by r.activity_id,
                        (r.created_at at time zone coalesce(u.timezone, 'UTC'))::date
         ) as day_total,
         row_number() over (
           partition by r.activity_id,
                        (r.created_at at time zone coalesce(u.timezone, 'UTC'))::date
           order by r.created_at desc, r.id
         ) as row_number,
         a.goal_target
    from public.reports r
    join public.activities a on a.id = r.activity_id
    join public.users u on u.id = a.user_id
   where a.completion_mode in ('counter', 'timer')
     and a.frequency <> 'once'
     and r.progress_value is not null
)
delete from public.reports r
 using ranked
 where r.id = ranked.id
   and (ranked.row_number > 1 or ranked.day_total < ranked.goal_target);

-- One-off counters/timers accumulate across days. Keep only the latest report
-- and only when the lifetime target was reached.
with ranked as (
  select r.id,
         (r.created_at at time zone coalesce(u.timezone, 'UTC'))::date as local_date,
         sum(r.progress_value) over (partition by r.activity_id) as total_progress,
         row_number() over (
           partition by r.activity_id
           order by r.created_at desc, r.id
         ) as row_number,
         a.goal_target
    from public.reports r
    join public.activities a on a.id = r.activity_id
    join public.users u on u.id = a.user_id
   where a.completion_mode in ('counter', 'timer')
     and a.frequency = 'once'
     and r.progress_value is not null
)
update public.reports r
   set progress_value = ranked.total_progress,
       progress_date = ranked.local_date
  from ranked
 where r.id = ranked.id
   and ranked.row_number = 1
   and ranked.total_progress >= ranked.goal_target;

with ranked as (
  select r.id,
         sum(r.progress_value) over (partition by r.activity_id) as total_progress,
         row_number() over (
           partition by r.activity_id
           order by r.created_at desc, r.id
         ) as row_number,
         a.goal_target
    from public.reports r
    join public.activities a on a.id = r.activity_id
   where a.completion_mode in ('counter', 'timer')
     and a.frequency = 'once'
     and r.progress_value is not null
)
delete from public.reports r
 using ranked
 where r.id = ranked.id
   and (ranked.row_number > 1 or ranked.total_progress < ranked.goal_target);

create unique index if not exists idx_reports_activity_progress_date
  on public.reports (activity_id, progress_date)
  where progress_date is not null;

comment on column public.reports.progress_date is
  'Server-owned local calendar day for a counter/timer target completion.';

create or replace function public.record_activity_progress(
  p_activity_id uuid,
  p_value double precision
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_activity record;
  v_timezone text;
  v_today date;
  v_daily_progress double precision;
  v_total_progress double precision;
  v_display_progress double precision;
  v_target_reached boolean;
  v_report_created boolean := false;
  v_report_count integer := 0;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if p_value is null or p_value <= 0 or p_value > 1000000 then
    raise exception 'Progress value must be between 0 and 1000000'
      using errcode = '22023';
  end if;

  select a.id, a.user_id, a.frequency, a.status, a.goal_target,
         a.goal_progress, a.completion_mode
    into v_activity
    from public.activities a
   where a.id = p_activity_id
   for update;

  if not found or v_activity.user_id is distinct from v_uid then
    raise exception 'Activity not found' using errcode = '42501';
  end if;
  if v_activity.status <> 'active' then
    raise exception 'Activity is not active' using errcode = '22023';
  end if;
  if v_activity.completion_mode not in ('counter', 'timer')
     or v_activity.goal_target is null
     or v_activity.goal_target <= 0 then
    raise exception 'Activity does not accept measurable progress'
      using errcode = '22023';
  end if;

  select coalesce(u.timezone, 'UTC')
    into v_timezone
    from public.users u
   where u.id = v_uid;
  v_timezone := coalesce(v_timezone, 'UTC');
  v_today := (now() at time zone v_timezone)::date;

  insert into public.activity_progress_entries (activity_id, user_id, value)
  values (p_activity_id, v_uid, p_value);

  select coalesce(sum(e.value), 0)
    into v_daily_progress
    from public.activity_progress_entries e
   where e.activity_id = p_activity_id
     and (e.created_at at time zone v_timezone)::date = v_today;

  select coalesce(sum(e.value), 0)
    into v_total_progress
    from public.activity_progress_entries e
   where e.activity_id = p_activity_id;

  if v_activity.frequency = 'once' then
    v_display_progress := v_total_progress;
  else
    v_display_progress := v_daily_progress;
  end if;

  update public.activities
     set goal_progress = v_display_progress
   where id = p_activity_id;

  v_target_reached := v_display_progress >= v_activity.goal_target;

  if v_target_reached then
    insert into public.reports (activity_id, progress_value, progress_date)
    values (p_activity_id, v_display_progress, v_today)
    on conflict (activity_id, progress_date)
      where progress_date is not null
      do nothing;
    get diagnostics v_report_count = row_count;
    v_report_created := v_report_count > 0;

    if v_activity.frequency = 'once' then
      update public.activities
         set status = 'completed'
       where id = p_activity_id;
    end if;
  end if;

  return jsonb_build_object(
    'activity_id', p_activity_id,
    'daily_progress', v_daily_progress,
    'total_progress', v_total_progress,
    'display_progress', v_display_progress,
    'target_reached', v_target_reached,
    'report_created', v_report_created
  );
end;
$$;

revoke execute on function public.record_activity_progress(uuid, double precision)
  from public, anon;
grant execute on function public.record_activity_progress(uuid, double precision)
  to authenticated;

create or replace function public.get_my_activity_progress_today()
returns table (
  activity_id uuid,
  daily_progress double precision,
  target_reached boolean
)
language sql
stable
security definer
set search_path = ''
as $$
  select a.id,
         coalesce(sum(e.value) filter (
           where (e.created_at at time zone coalesce(u.timezone, 'UTC'))::date
                 = (now() at time zone coalesce(u.timezone, 'UTC'))::date
         ), 0)::double precision as daily_progress,
         (
           coalesce(sum(e.value) filter (
             where (e.created_at at time zone coalesce(u.timezone, 'UTC'))::date
                   = (now() at time zone coalesce(u.timezone, 'UTC'))::date
           ), 0) >= a.goal_target
         ) as target_reached
    from public.activities a
    join public.users u on u.id = a.user_id
    left join public.activity_progress_entries e on e.activity_id = a.id
   where a.user_id = auth.uid()
     and a.status = 'active'
     and a.frequency <> 'once'
     and a.completion_mode in ('counter', 'timer')
     and a.goal_target > 0
   group by a.id, a.goal_target;
$$;

revoke execute on function public.get_my_activity_progress_today()
  from public, anon;
grant execute on function public.get_my_activity_progress_today()
  to authenticated;

create or replace function public.reset_activity_progress_today(p_activity_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_activity record;
  v_timezone text;
  v_today date;
  v_remaining double precision;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  select a.id, a.user_id, a.frequency, a.goal_target
    into v_activity
    from public.activities a
   where a.id = p_activity_id
   for update;

  if not found or v_activity.user_id is distinct from v_uid then
    raise exception 'Activity not found' using errcode = '42501';
  end if;

  select coalesce(u.timezone, 'UTC')
    into v_timezone
    from public.users u
   where u.id = v_uid;
  v_timezone := coalesce(v_timezone, 'UTC');
  v_today := (now() at time zone v_timezone)::date;

  delete from public.activity_progress_entries e
   where e.activity_id = p_activity_id
     and (e.created_at at time zone v_timezone)::date = v_today;

  delete from public.reports r
   where r.activity_id = p_activity_id
     and r.progress_date = v_today;

  if v_activity.frequency = 'once' then
    select coalesce(sum(e.value), 0)
      into v_remaining
      from public.activity_progress_entries e
     where e.activity_id = p_activity_id;
  else
    v_remaining := 0;
  end if;

  update public.activities
     set goal_progress = v_remaining,
         status = case
           when v_activity.frequency = 'once'
                and v_remaining < coalesce(v_activity.goal_target, 0)
             then 'active'
           else status
         end
   where id = p_activity_id;
end;
$$;

revoke execute on function public.reset_activity_progress_today(uuid)
  from public, anon;
grant execute on function public.reset_activity_progress_today(uuid)
  to authenticated;

-- Recurring goal_progress is a day-scoped display cache from now on. The RPC
-- and the app's load path repopulate it for the user's current local day.
update public.activities
   set goal_progress = 0
 where frequency <> 'once'
   and completion_mode in ('counter', 'timer');
