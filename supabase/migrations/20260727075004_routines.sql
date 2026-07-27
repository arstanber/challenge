-- Ordered routines group existing activities without duplicating their
-- completion state. TaskEngine/reports remain the only completion source.

create table public.routines (
  id uuid primary key default uuid_generate_v4(),
  user_id uuid not null references public.users(id) on delete cascade,
  name text not null check (char_length(btrim(name)) between 1 and 80),
  icon text not null default 'sun.max.fill'
    check (char_length(icon) between 1 and 50),
  period text not null default 'anytime'
    check (period in ('morning', 'evening', 'anytime')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index idx_routines_user_updated
  on public.routines (user_id, updated_at desc);

create table public.routine_items (
  id uuid primary key default uuid_generate_v4(),
  routine_id uuid not null references public.routines(id) on delete cascade,
  activity_id uuid not null references public.activities(id) on delete cascade,
  user_id uuid not null references public.users(id) on delete cascade,
  position integer not null check (position >= 0 and position < 20),
  created_at timestamptz not null default now(),
  unique (routine_id, activity_id),
  unique (routine_id, position)
);

create index idx_routine_items_user
  on public.routine_items (user_id);

create index idx_routine_items_activity
  on public.routine_items (activity_id);

alter table public.routines enable row level security;
alter table public.routine_items enable row level security;

grant select, insert, update, delete on table public.routines to authenticated;
grant select, insert, update, delete on table public.routine_items to authenticated;
revoke all on table public.routines from anon;
revoke all on table public.routine_items from anon;

create policy "Users read own routines"
  on public.routines for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users create own routines"
  on public.routines for insert
  to authenticated
  with check ((select auth.uid()) = user_id);

create policy "Users update own routines"
  on public.routines for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check ((select auth.uid()) = user_id);

create policy "Users delete own routines"
  on public.routines for delete
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users read own routine items"
  on public.routine_items for select
  to authenticated
  using ((select auth.uid()) = user_id);

create policy "Users create own routine items"
  on public.routine_items for insert
  to authenticated
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1
        from public.routines r
       where r.id = routine_id
         and r.user_id = (select auth.uid())
    )
    and exists (
      select 1
        from public.activities a
       where a.id = activity_id
         and a.user_id = (select auth.uid())
         and a.status = 'active'
    )
  );

create policy "Users update own routine items"
  on public.routine_items for update
  to authenticated
  using ((select auth.uid()) = user_id)
  with check (
    (select auth.uid()) = user_id
    and exists (
      select 1
        from public.routines r
       where r.id = routine_id
         and r.user_id = (select auth.uid())
    )
    and exists (
      select 1
        from public.activities a
       where a.id = activity_id
         and a.user_id = (select auth.uid())
         and a.status = 'active'
    )
  );

create policy "Users delete own routine items"
  on public.routine_items for delete
  to authenticated
  using ((select auth.uid()) = user_id);

create or replace function public.get_my_routines()
returns table (
  id uuid,
  user_id uuid,
  name text,
  icon text,
  period text,
  activity_ids uuid[],
  created_at timestamptz
)
language sql
stable
security invoker
set search_path = ''
as $$
  select r.id,
         r.user_id,
         r.name,
         r.icon,
         r.period,
         array_agg(ri.activity_id order by ri.position) as activity_ids,
         r.created_at
    from public.routines r
    join public.routine_items ri on ri.routine_id = r.id
   where r.user_id = auth.uid()
   group by r.id
   order by
     case r.period
       when 'morning' then 0
       when 'evening' then 1
       else 2
     end,
     r.updated_at desc;
$$;

revoke execute on function public.get_my_routines() from public, anon;
grant execute on function public.get_my_routines() to authenticated;

create or replace function public.save_my_routine(
  p_routine_id uuid,
  p_name text,
  p_icon text,
  p_period text,
  p_activity_ids uuid[]
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_name text := btrim(p_name);
  v_icon text := btrim(p_icon);
  v_activity_count integer;
begin
  if v_uid is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;
  if p_routine_id is null then
    raise exception 'Routine id is required' using errcode = '22023';
  end if;
  if char_length(v_name) not between 1 and 80 then
    raise exception 'Routine name must contain 1 to 80 characters'
      using errcode = '22023';
  end if;
  if char_length(v_icon) not between 1 and 50 then
    raise exception 'Routine icon must contain 1 to 50 characters'
      using errcode = '22023';
  end if;
  if p_period not in ('morning', 'evening', 'anytime') then
    raise exception 'Invalid routine period' using errcode = '22023';
  end if;
  if coalesce(cardinality(p_activity_ids), 0) not between 1 and 20 then
    raise exception 'Routine must contain 1 to 20 activities'
      using errcode = '22023';
  end if;

  select count(distinct activity_id)
    into v_activity_count
    from unnest(p_activity_ids) as ids(activity_id);
  if v_activity_count <> cardinality(p_activity_ids) then
    raise exception 'Routine activities must be unique'
      using errcode = '22023';
  end if;

  select count(*)
    into v_activity_count
    from public.activities a
   where a.id = any(p_activity_ids)
     and a.user_id = v_uid
     and a.status = 'active';
  if v_activity_count <> cardinality(p_activity_ids) then
    raise exception 'Routine contains an unavailable activity'
      using errcode = '42501';
  end if;

  insert into public.routines (id, user_id, name, icon, period)
  values (p_routine_id, v_uid, v_name, v_icon, p_period)
  on conflict (id) do update
    set name = excluded.name,
        icon = excluded.icon,
        period = excluded.period,
        updated_at = now()
  where routines.user_id = v_uid;

  if not exists (
    select 1
      from public.routines r
     where r.id = p_routine_id
       and r.user_id = v_uid
  ) then
    raise exception 'Routine not found' using errcode = '42501';
  end if;

  delete from public.routine_items ri
   where ri.routine_id = p_routine_id
     and ri.user_id = v_uid;

  insert into public.routine_items (
    routine_id,
    activity_id,
    user_id,
    position
  )
  select p_routine_id,
         ordered.activity_id,
         v_uid,
         (ordered.ordinality - 1)::integer
    from unnest(p_activity_ids) with ordinality
      as ordered(activity_id, ordinality);

  return p_routine_id;
end;
$$;

revoke execute on function public.save_my_routine(
  uuid,
  text,
  text,
  text,
  uuid[]
) from public, anon;
grant execute on function public.save_my_routine(
  uuid,
  text,
  text,
  text,
  uuid[]
) to authenticated;
