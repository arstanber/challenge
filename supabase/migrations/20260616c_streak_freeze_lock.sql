-- Fix an overdraw race in use_streak_freeze: two concurrent calls could both
-- pass the freezes_available() check before either insert landed, spending more
-- freezes than the wallet holds. Serialize per-user by taking a row lock on the
-- users row before reading the balance. Body otherwise matches
-- 20260613b_streak_freezes.sql.

create or replace function public.use_streak_freeze(p_date date default null)
returns jsonb
language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_tz text; v_today date; v_target date; v_avail int;
  g record;
begin
  if v_uid is null then raise exception 'not authenticated'; end if;

  -- Serialize concurrent freeze spends for this user so the availability check
  -- and the insert below cannot interleave and overdraw the wallet.
  perform 1 from users where id = v_uid for update;

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
