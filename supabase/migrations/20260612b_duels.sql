-- Friend duels: challenge a friend to close at least one task every day
-- for N days (3-30, default 7). Joined by a 6-char invite code, same
-- pattern as family invites.
--
-- Day rule (deliberately simpler than the 75% streak rule, so a duel stays
-- legible): a duel day counts for a participant when they have >= 1 report
-- with ai_result in ('approved','not_applicable','pending') that day,
-- bucketed in their own timezone -- same qualifying-report rule as the
-- streak engine. Winner = more counted days; tie = no winner_id (both held).
--
-- All writes go through SECURITY DEFINER RPCs; the table itself is
-- select-only for participants.

create table if not exists public.duels (
  id            uuid primary key default uuid_generate_v4(),
  challenger_id uuid not null references public.users(id) on delete cascade,
  opponent_id   uuid references public.users(id) on delete cascade,
  invite_code   text not null unique,
  days          smallint not null default 7 check (days between 3 and 30),
  status        text not null default 'pending'
                check (status in ('pending', 'active', 'finished', 'cancelled')),
  starts_on     date,
  ends_on       date,
  winner_id     uuid references public.users(id),
  created_at    timestamptz not null default now()
);

alter table public.duels enable row level security;

drop policy if exists "Participants can read their duels" on public.duels;
create policy "Participants can read their duels"
  on public.duels for select
  using (auth.uid() = challenger_id or auth.uid() = opponent_id);

create index if not exists idx_duels_challenger on public.duels (challenger_id);
create index if not exists idx_duels_opponent on public.duels (opponent_id);

-- ============ helpers ============

-- Qualifying days for a user inside a window, bucketed in their timezone.
create or replace function public.duel_days_done(p_user uuid, p_from date, p_to date)
returns date[]
language sql stable security definer set search_path = public as $$
  select coalesce(array_agg(distinct s.day order by s.day), '{}') from (
    select (r.created_at at time zone coalesce(u.timezone, 'UTC'))::date as day
    from reports r
    join activities a on a.id = r.activity_id
    join users u on u.id = a.user_id
    where a.user_id = p_user
      and r.ai_result in ('approved', 'not_applicable', 'pending')
  ) s
  where p_from is not null and p_to is not null
    and s.day between p_from and p_to;
$$;

revoke execute on function public.duel_days_done(uuid, date, date) from public, anon, authenticated;

-- ============ RPCs ============

create or replace function public.create_duel(p_days int default 7)
returns duels
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_code text;
  v_row duels;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  if p_days not between 3 and 30 then raise exception 'days out of range'; end if;
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

create or replace function public.join_duel(p_code text)
returns duels
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_tz text;
  v_today date;
  v_row duels;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;
  select * into v_row from duels
  where invite_code = upper(trim(p_code)) and status = 'pending'
  for update;
  if not found then raise exception 'duel not found or already started'; end if;
  if v_row.challenger_id = v_uid then raise exception 'cannot duel yourself'; end if;

  select coalesce(timezone, 'UTC') into v_tz from users where id = v_uid;
  v_today := (now() at time zone v_tz)::date;

  update duels
  set opponent_id = v_uid,
      status      = 'active',
      starts_on   = v_today,
      ends_on     = v_today + v_row.days - 1
  where id = v_row.id
  returning * into v_row;
  return v_row;
end $$;

grant execute on function public.join_duel(text) to authenticated;
revoke execute on function public.join_duel(text) from public, anon;

create or replace function public.cancel_duel(p_duel_id uuid)
returns void
language plpgsql security definer set search_path = public as $$
begin
  update duels set status = 'cancelled'
  where id = p_duel_id and challenger_id = auth.uid() and status = 'pending';
end $$;

grant execute on function public.cancel_duel(uuid) to authenticated;
revoke execute on function public.cancel_duel(uuid) from public, anon;

-- Finalize an overdue duel; idempotent, callable by either participant.
-- Due only when the window is over in BOTH participants' local dates.
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

  v_ch := coalesce(array_length(duel_days_done(v_row.challenger_id, v_row.starts_on, v_row.ends_on), 1), 0);
  v_op := coalesce(array_length(duel_days_done(v_row.opponent_id,   v_row.starts_on, v_row.ends_on), 1), 0);

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

-- Everything the duel list/detail screens need in one round trip.
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
                          else to_jsonb(duel_days_done(d.opponent_id, d.starts_on, d.ends_on)) end);
  end loop;
  return result;
end $$;

grant execute on function public.get_my_duels() to authenticated;
revoke execute on function public.get_my_duels() from public, anon;
