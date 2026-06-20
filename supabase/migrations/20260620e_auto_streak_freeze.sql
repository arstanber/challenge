-- ============ Auto-apply a streak freeze on a missed day ============
-- Duolingo-style: when the user comes back and yesterday was missed, spend one
-- freeze automatically to bridge the gap -- but ONLY when it actually rescues a
-- live run (the day before yesterday still counted) so we never fabricate a
-- streak out of nothing or waste a freeze on an already-dead run.
--
-- This runs inside refresh_my_streaks (called on every app load), so the rescue
-- happens the moment the user returns. Day boundaries use the user's timezone.
-- Idempotent: the unique (user_id, frozen_date) key + the "not already frozen"
-- guard mean repeated refreshes never double-spend. Auto rows are tagged
-- source = 'auto' to tell them apart from manual freezes.
--
-- Limitation (by design): a single freeze only bridges one missed day. Two
-- consecutive misses without an app open in between still break the run -- a
-- nightly server cron would be needed to cover that, which is out of scope here.
create or replace function public.refresh_my_streaks()
returns jsonb language plpgsql security definer set search_path = public as $$
declare
  v_uid uuid := auth.uid();
  v_tz text; v_today date; v_yesterday date; v_before date;
  g record; a record; s record;
  acts jsonb := '[]'::jsonb;
  v_avail int; v_yest_freezable boolean; v_yest_frozen boolean; v_auto boolean := false;
  v_run_alive boolean;
begin
  if v_uid is null then
    raise exception 'not authenticated';
  end if;
  select coalesce(timezone, 'UTC') into v_tz from users where id = v_uid;
  v_today := (now() at time zone v_tz)::date;
  v_yesterday := v_today - 1;
  v_before := v_today - 2;

  -- Auto-rescue yesterday before computing the streak.
  if not day_qualifies(v_uid, v_yesterday)
     and not exists (select 1 from streak_freezes where user_id = v_uid and frozen_date = v_yesterday)
  then
    -- Only worth a freeze if the run was still alive the day before yesterday.
    v_run_alive := day_qualifies(v_uid, v_before)
      or exists (select 1 from streak_freezes where user_id = v_uid and frozen_date = v_before);
    if v_run_alive and freezes_available(v_uid) > 0 then
      insert into streak_freezes (user_id, frozen_date, source)
      values (v_uid, v_yesterday, 'auto')
      on conflict (user_id, frozen_date) do nothing;
    end if;
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

  select source = 'auto' into v_auto
  from streak_freezes where user_id = v_uid and frozen_date = v_yesterday;
  v_yest_frozen := v_auto is not null;
  v_auto := coalesce(v_auto, false);

  v_avail := freezes_available(v_uid);
  v_yest_freezable := v_avail > 0
    and not day_qualifies(v_uid, v_yesterday)
    and not v_yest_frozen;

  return jsonb_build_object(
    'global_current',       g.current_streak,
    'global_best',          g.best_streak,
    'today_count',          g.today_count,
    'activities',           acts,
    'freezes_available',    v_avail,
    'yesterday_freezable',  v_yest_freezable,
    'yesterday_frozen',     v_yest_frozen,
    'yesterday_auto_frozen', v_auto);
end $$;

grant execute on function public.refresh_my_streaks() to authenticated;
