-- Duels v2: longer windows + winner decided by total tasks completed.
--
-- Changes:
--   1) days range widened from 3..30 to 3..90.
--   2) New scoring: the winner is whoever completed MORE tasks over the window
--      ("больше дел"), not whoever covered more days. A "task" = one distinct
--      activity completed on a given day (so re-submitting the same task the
--      same day can't inflate the score). The per-day grid still ships for the
--      visual, but finish_duel_if_due and the headline score use task counts.

-- 1. Widen the days range -----------------------------------------------------
alter table public.duels drop constraint if exists duels_days_check;
alter table public.duels add constraint duels_days_check check (days between 3 and 90);

-- 2. Total tasks completed by a user inside a window, bucketed in their tz.
--    Distinct (activity, day) so duplicate same-day reports count once.
create or replace function public.duel_tasks_done(p_user uuid, p_from date, p_to date)
returns int
language sql stable security definer set search_path = public as $$
  select coalesce(count(*), 0)::int from (
    select distinct r.activity_id,
           (r.created_at at time zone coalesce(u.timezone, 'UTC'))::date as day
    from reports r
    join activities a on a.id = r.activity_id
    join users u on u.id = a.user_id
    where a.user_id = p_user
      and r.ai_result in ('approved', 'not_applicable', 'pending')
  ) s
  where p_from is not null and p_to is not null
    and s.day between p_from and p_to;
$$;

revoke execute on function public.duel_tasks_done(uuid, date, date) from public, anon, authenticated;

-- 3. create_duel: accept up to 90 days.
create or replace function public.create_duel(p_days int default 7)
returns duels
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_code text;
  v_row duels;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if p_days not between 3 and 90 then raise exception 'days out of range'; end if;
  loop
    v_code := upper(substr(md5(random()::text), 1, 6));
    exit when not exists (select 1 from duels where invite_code = v_code);
  end loop;
  insert into duels (challenger_id, invite_code, days)
  values (v_uid, v_code, p_days)
  returning * into v_row;
  return v_row;
end $$;

grant execute on function public.create_duel(int) to authenticated;
revoke execute on function public.create_duel(int) from public, anon;

-- 4. finish_duel_if_due: winner = more tasks completed.
create or replace function public.finish_duel_if_due(p_duel_id uuid)
returns duels
language plpgsql security definer set search_path = public as $$
declare
  v_row duels;
  v_tz text;
  v_ch int;
  v_op int;
begin
  select * into v_row from duels where id = p_duel_id for update;
  if not found then raise exception 'duel not found'; end if;
  if auth.uid() is distinct from v_row.challenger_id
     and auth.uid() is distinct from v_row.opponent_id then
    raise exception 'not a participant';
  end if;
  if v_row.status <> 'active' then return v_row; end if;

  select coalesce(timezone, 'UTC') into v_tz from users where id = v_row.challenger_id;
  if (now() at time zone v_tz)::date <= v_row.ends_on then return v_row; end if;
  select coalesce(timezone, 'UTC') into v_tz from users where id = v_row.opponent_id;
  if (now() at time zone v_tz)::date <= v_row.ends_on then return v_row; end if;

  v_ch := duel_tasks_done(v_row.challenger_id, v_row.starts_on, v_row.ends_on);
  v_op := duel_tasks_done(v_row.opponent_id,   v_row.starts_on, v_row.ends_on);

  update duels
  set status    = 'finished',
      winner_id = case when v_ch > v_op then challenger_id
                       when v_op > v_ch then opponent_id
                       else null end
  where id = v_row.id
  returning * into v_row;
  return v_row;
end $$;

grant execute on function public.finish_duel_if_due(uuid) to authenticated;
revoke execute on function public.finish_duel_if_due(uuid) from public, anon;

-- 5. get_my_duels: add per-side task counts alongside the day arrays.
create or replace function public.get_my_duels()
returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  result jsonb := '[]'::jsonb;
  d record;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  for d in
    select dl.*,
           cu.email as challenger_email,
           ou.email as opponent_email
    from duels dl
    join users cu on cu.id = dl.challenger_id
    left join users ou on ou.id = dl.opponent_id
    where dl.challenger_id = v_uid or dl.opponent_id = v_uid
    order by dl.created_at desc
    limit 50
  loop
    result := result || jsonb_build_object(
      'id',               d.id,
      'challenger_id',    d.challenger_id,
      'opponent_id',      d.opponent_id,
      'invite_code',      d.invite_code,
      'days',             d.days,
      'status',           d.status,
      'starts_on',        d.starts_on,
      'ends_on',          d.ends_on,
      'winner_id',        d.winner_id,
      'created_at',       d.created_at,
      'challenger_email', d.challenger_email,
      'opponent_email',   d.opponent_email,
      'challenger_done',  case when d.starts_on is null then '[]'::jsonb
                          else to_jsonb(duel_days_done(d.challenger_id, d.starts_on, d.ends_on)) end,
      'opponent_done',    case when d.starts_on is null or d.opponent_id is null then '[]'::jsonb
                          else to_jsonb(duel_days_done(d.opponent_id, d.starts_on, d.ends_on)) end,
      'challenger_tasks', case when d.starts_on is null then 0
                          else duel_tasks_done(d.challenger_id, d.starts_on, d.ends_on) end,
      'opponent_tasks',   case when d.starts_on is null or d.opponent_id is null then 0
                          else duel_tasks_done(d.opponent_id, d.starts_on, d.ends_on) end);
  end loop;
  return result;
end $$;

grant execute on function public.get_my_duels() to authenticated;
revoke execute on function public.get_my_duels() from public, anon;
