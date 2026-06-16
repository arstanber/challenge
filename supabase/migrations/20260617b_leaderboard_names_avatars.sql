-- Leaderboard shows display names + avatars instead of raw emails. Adds
-- display_name and avatar_url to the returned shape. Return type changes, so the
-- function must be dropped and recreated. Logic is otherwise identical to
-- 20260610b_task_core_redesign.sql.

drop function if exists get_leaderboard(uuid);

create function get_leaderboard(p_user_id uuid)
returns table (
    rank            bigint,
    user_id         uuid,
    email           text,
    display_name    text,
    avatar_url      text,
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
        coalesce(nullif(u.display_name, ''), split_part(u.email, '@', 1)) as display_name,
        u.avatar_url,
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
revoke execute on function get_leaderboard(uuid) from public, anon;
