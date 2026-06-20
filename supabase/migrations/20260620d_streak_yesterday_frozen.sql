-- ============ refresh_my_streaks: expose "yesterday was frozen" ============
-- Adds one backward-compatible key: yesterday_frozen -- true when a freeze row
-- already covers yesterday (the freeze that is currently holding the run).
-- The app paints the streak flame blue in that case, gray when today is still
-- unfinished, orange once today's goal is met. Day boundaries use the user's
-- timezone (same as the rest of this RPC), so the client must not re-derive it.
create or replace function public.refresh_my_streaks()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_tz text; v_today date; v_yesterday date;
  g record; a record; s record;
  acts jsonb := '[]'::jsonb;
  v_avail int; v_yest_freezable boolean; v_yest_frozen boolean;
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

  v_yest_frozen := exists (
    select 1 from streak_freezes where user_id = v_uid and frozen_date = v_yesterday);
  v_avail := freezes_available(v_uid);
  v_yest_freezable := v_avail > 0
    and not day_qualifies(v_uid, v_yesterday)
    and not v_yest_frozen;

  return jsonb_build_object(
    'global_current',      g.current_streak,
    'global_best',         g.best_streak,
    'today_count',         g.today_count,
    'activities',          acts,
    'freezes_available',   v_avail,
    'yesterday_freezable', v_yest_freezable,
    'yesterday_frozen',    v_yest_frozen);
end $$;

grant execute on function public.refresh_my_streaks() to authenticated;
